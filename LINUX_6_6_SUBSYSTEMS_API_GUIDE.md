# Linux 6.6 内核安全、文件、进程子系统与开发接口导读

本文基于 `linker99/linux` 的 Linux 6.6 代码结构整理，重点介绍：

- 安全子系统（LSM / capability / credentials）
- 文件系统子系统（VFS / inode / file / superblock）
- 进程子系统（task / pid / signal / scheduler）
- 面向开发者最重要的内核 API 接口与功能定位
- 按“重要性”和“常用度”排序的快速索引表

> 说明：本文不是系统调用手册，而是内核开发/模块开发视角下的接口导读。Linux 内核中的 API 设计并不保证对外稳定；很多接口仅适用于内核内部使用。

## 1. Linux 6.6 内核的三大核心子系统

### 1.1 安全子系统

核心头文件：

- `include/linux/security.h`
- `include/linux/capability.h`
- `include/linux/cred.h`

作用：

- 进行权限判定
- 管理 credentials（进程凭据）
- 通过 LSM（Linux Security Modules）控制文件、进程、网络、IPC 等操作
- 维护能力集（capabilities）和安全上下文

关键概念：

- `struct cred`：进程凭据对象，保存 UID/GID/capabilities/user namespace 等信息
- `capable()` / `ns_capable()`：检查当前任务是否具备某个 capability
- `prepare_creds()` / `commit_creds()`：更新进程凭据的标准方式
- LSM hooks：`security_inode_permission()`、`security_file_permission()`、`security_task_*()` 等

### 1.2 文件系统子系统

核心头文件：

- `include/linux/fs.h`
- `include/linux/fs/super.h`
- `include/linux/dcache.h`

作用：

- 抽象 inode、dentry、file、super_block
- 管理 VFS（Virtual File System）统一接口
- 提供文件、目录、挂载、权限与页缓存的通用机制

关键概念：

- `struct file_operations`：文件对象的回调集合
- `struct inode_operations`：inode/目录操作集合
- `struct address_space_operations`：页缓存和 folio 读写模型
- `struct file_system_type`：注册文件系统类型
- `struct super_block`：一个挂载实例对应一个 superblock

### 1.3 进程子系统

核心头文件：

- `include/linux/sched.h`
- `include/linux/pid.h`
- `include/linux/signal.h`

作用：

- 管理 task_struct、PID、线程组、调度器状态
- 处理唤醒、睡眠、yield、调度策略
- 管理信号、等待队列等进程同步机制

关键概念：

- `struct task_struct`：进程/线程描述符
- `struct pid`：PID 及命名空间语义
- `wake_up_process()`：唤醒指定任务
- `schedule()`：主动让出 CPU
- `wait_event*()` 系列：等待条件变为真

---

## 2. 安全子系统：最重要的开发者接口排序

参考：

- `include/linux/security.h`
- `include/linux/capability.h`
- `include/linux/cred.h`

| 排序 | 接口 / 接口族 | 重要性 | 常用度 | 主要功能 |
|---:|---|---|---|---|
| 1 | `capable()`、`ns_capable()` | 很高 | 常用 | 检查当前任务是否拥有某个 capability；可按 namespace 过滤。用于权限判定的常用入口。 |
| 2 | `prepare_creds()`、`commit_creds()`、`abort_creds()` | 很高 | 常用 | 按 COW（Copy-On-Write）方式准备和提交进程凭据；修改 UID/GID/能力时的标准接口。 |
| 3 | `current_cred()`、`get_task_cred()`、`put_cred()` | 高 | 常用 | 获取当前或其他任务的凭据；在读取和使用任务凭据时必须正确获取/释放引用。 |
| 4 | `security_inode_permission()`、`security_file_permission()` | 很高 | 常用 | 让 VFS 等内核子系统在执行 inode / file 权限判断时进入 LSM 逻辑。 |
| 5 | `security_bprm_*()`、`security_task_*()` | 高 | 特定 | 覆盖程序执行、任务属性修���、进程相关安全检查等。 |
| 6 | `security_sb_*()`、`security_inode_*()` | 高 | 文件系统开发中常用 | 对挂载、inode 创建/删除、xattr、权限等安全检查进行挂钩。 |
| 7 | `securityfs_create_file()`、`securityfs_create_dir()` | 中 | 特定 | 在 `securityfs` 中暴露安全模块状态/配置的接口。 |
| 8 | `security_locked_down()` | 中 | 特定 | 检查是否受到内核 lockdown 约束，防止关键操作绕过安全策略。 |

### 安全接口简述

1. `capable()` / `ns_capable()`
   - 最常见的 capability 判定入口。
   - 用于：是否具备 `CAP_SYS_ADMIN`、`CAP_NET_ADMIN` 等权限能力。

2. `prepare_creds()` / `commit_creds()`
   - 这是内核中安全地修改当前任务 credentials 的标准方法。
   - 适用于：提升/降级权限、替换 namespace 视角、设置能力等。

3. `current_cred()` / `get_task_cred()`
   - 获取任务的“客观/主观”安全上下文。
   - 一旦拿到了 cred，通常要使用 `put_cred()` 释放引用。

4. `security_inode_permission()`
   - 文件操作前权限检查的关键入口之一。
   - LSM 会在这里决定是否允许 `read/write/execute` 等动作。

5. `security_task_kill()` / `security_task_prctl()` / `security_task_setnice()`
   - 控制发送信号、修改任��调度属性、控制特权任务行为等。

---

## 3. 文件系统子系统：最重要的开发者接口排序

参考：`include/linux/fs.h`

| 排序 | 接口 / 接口族 | 重要性 | 常用度 | 主要功能 |
|---:|---|---|---|---|
| 1 | `struct file_operations` | 很高 | 很常用 | 定义字符设备、块设备、伪文件、文件系统对象的方法：`open`、`read`、`write`、`poll`、`mmap`、`ioctl` 等。 |
| 2 | `struct inode_operations` | 很高 | 文件系统开发中很常用 | 定义 inode 级别操作：`lookup`、`create`、`rename`、`link`、`unlink`、`permission`、`getattr` 等。 |
| 3 | `struct address_space_operations` | 高 | 文件系统开发中常用 | 定义页缓存和 folio 读写模型：`read_folio`、`writepages`、`write_begin`、`write_end`、`direct_IO` 等。 |
| 4 | `struct file_system_type` | 很高 | 文件系统开发中常用 | 描述新的文件系统类型，并用 `register_filesystem()` / `unregister_filesystem()` 注册。 |
| 5 | `vfs_create()`、`vfs_mkdir()`、`vfs_link()`、`vfs_rename()` | 高 | 常用 | 按 VFS 统一流程执行目录项变更，减少重复实现安全与同步逻辑。 |
| 6 | `iget_locked()`、`iget5_locked()`、`iput()` | 高 | 常用 | inode 的查找、创建和引用计数管理。 |
| 7 | `inode_lock()`、`inode_unlock()`、`i_size_read()`、`i_size_write()` | 高 | 常用 | inode 同步、锁保护、inode 大小访问。 |
| 8 | `generic_file_read_iter()`、`generic_file_write_iter()` | 高 | 常用 | 提供常见的泛型文件读写逻辑，适合页缓存型文件系统复用。 |
| 9 | `kernel_read()`、`kernel_write()` | 中高 | 常用 | 在内核上下文读取/写入文件，不依赖用户态应用层。 |
| 10 | `filemap_read()`、`filemap_splice_read()` | 中 | 特定 | 利用 page cache 实现高层文件 I/O 逻辑。 |
| 11 | `generic_file_mmap()` | 中 | 特定 | 为普通文件提供 mmap 支持。 |

### 文件系统接口简述

1. `struct file_operations`
   - 是几乎所有文件/设备驱动的核心接口结构。
   - 对应真实的 `open/read/write/ioctl/poll/release` 等。

2. `struct inode_operations`
   - 处理目录树层面的语义：创建、删除、重命名、权限、链接等。
   - 比较典型的实现者是各类文件系统（ext4、xfs、overlayfs 等）。

3. `struct address_space_operations`
   - 负责页缓存、缓存一致性、writeback、readahead 等内部机制。
   - 这部分对高性能文件系统非常关键。

4. `register_filesystem()`
   - 一旦文件系统被注册，用户态就能通过 mount 进行挂载。

5. `vfs_*` helper
   - 为文件系统开发者节省大量重复安全检查和锁处理工作。

---

## 4. 进程子系统：最重要的开发者接口排序

参考：

- `include/linux/sched.h`
- `include/linux/pid.h`
- `include/linux/signal.h`

| 排序 | 接口 / 接口族 | 重要性 | 常用度 | 主要功能 |
|---:|---|---|---|---|
| 1 | `struct task_struct` 与 `current` | 很高 | 很常用 | 任务描述符与当前任务指针，进程管理的中心对象。 |
| 2 | `schedule()`、`schedule_timeout()`、`cond_resched()` | 很高 | 很常用 | 让出 CPU，延时等待，或者在长期循环中给调度器机会。 |
| 3 | `wake_up_process()`、`wake_up_state()` | 高 | 常用 | 唤醒指定任务；常用于等待队列、事件通知和同步机制。 |
| 4 | `wait_event*()`、`wake_up*()` | 很高 | 很常用 | 内核中最常见的同步模式：等待某条件变真，然后唤醒等待者。 |
| 5 | `find_task_by_vpid()`、`find_get_task_by_vpid()` | 高 | 常用 | 按虚拟 PID 寻找任务。 |
| 6 | `get_pid()` / `put_pid()` / `pid_nr_ns()` | 高 | 常用 | 处理 PID 引用计数和 namespace 语义。 |
| 7 | `set_cpus_allowed_ptr()`、`sched_setaffinity()` | 中高 | 特定 | 设置任务 CPU 亲和性。 |
| 8 | `sched_setscheduler()`、`sched_setattr()` | 中高 | 特定 | 调整调度策略和调度参数。 |
| 9 | `do_send_sig_info()`、`group_send_sig_info()` | 中 | 特定 | 发送信号给任务或线程组。 |
| 10 | `kernel_execve()` | 中 | 特定 | 在内核上下文执行目标程序。 |

### 进程接口简述

1. `current` / `struct task_struct`
   - 这是最核心的运行时对象，承载线程状态、权限、打开文件、信号、调度状态等。

2. `schedule()` / `cond_resched()`
   - 内核中大量同步和等待逻辑依赖这里的调度机制。
   - 需要注意：不能在不允许睡眠的上下文中随意调用阻塞式逻辑。

3. `wake_up_process()`
   - 任务解除睡眠、按条件继续执行。
   - 典型用法在等待队列、事件驱动和 worker 线程模型中。

4. `wait_event*()`
   - 这是最重要的“条件同步”接口之一。
   - 大量内核代码都使用它来等待资源、状态变更和事件完成。

5. `struct pid`
   - 处理 PID 的 namespace、引用计数和 task 批量关联。
   - 对多容器、多命名空间场景很关键。

---

## 5. 综合排序：开发者最常使用的接口

如果把“重要性”和“常用度”合并，最值得学习的顺序推荐如下：

1. `struct task_struct` / `current`
2. `struct file_operations`
3. `struct inode_operations`
4. `struct cred` / `prepare_creds()` / `commit_creds()`
5. `capable()` / `ns_capable()`
6. `schedule()` / `wake_up_process()` / `wait_event*()`
7. `struct file_system_type` / `register_filesystem()`
8. `iget_locked()` / `iput()`
9. `generic_file_read_iter()` / `generic_file_write_iter()`
10. `kernel_read()` / `kernel_write()`
11. `find_task_by_vpid()` / `struct pid`
12. `security_inode_permission()` / `security_file_permission()`

---

## 6. 实用建议

### 6.1 做驱动开发时

优先掌握：

- `file_operations`
- `open/release/read/write/ioctl/poll`
- `wait_event*()` / `wake_up*()`
- 设备号管理和内核内存分配

### 6.2 做文件系统开发时

优先掌握：

- `inode_operations`
- `file_operations`
- `address_space_operations`
- `super_block` / `file_system_type`
- `iget_locked()` / `iput()`
- VFS helper (`vfs_*`)

### 6.3 做安全与权限开发时

优先掌握：

- `struct cred`
- `prepare_creds()` / `commit_creds()`
- `capable()` / `ns_capable()`
- LSM hooks 与 module security 路径

### 6.4 做进程/调度器开发时

优先掌握：

- `task_struct`
- `current`
- `schedule()`
- `wake_up_process()`
- `pid` 相关 API
- signal send path

---

## 7. 结论

Linux 6.6 内核中，最关键的三类开发接口可以概括为：

- 安全：`cred` + `capability` + LSM hook
- 文件：`file_operations` + `inode_operations` + `address_space_operations`
- 进程：`task_struct` + `pid` + `schedule` + `signal`

如果要真正写内核代码，不建议直接“硬编码”访问大量内部结构字段；更合理的方法是：

- 先了解统一抽象层（VFS、LSM、调度器、PID 框架）
- 再选择最贴近需求的 API
- 最后再决定是否直接访问特定结构体字段

这能最大程度保证代码兼容、可维护性和正确性。

---

## 8. 参考入口

- `include/linux/security.h`
- `include/linux/capability.h`
- `include/linux/cred.h`
- `include/linux/fs.h`
- `include/linux/sched.h`
- `include/linux/pid.h`
- `include/linux/signal.h`

本文内容已根据 Linux 6.6 源码结构整理，适合作为内核开发入门的快速导航文档。
