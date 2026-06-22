.. SPDX-License-Identifier: GPL-2.0

=========================================
Understanding inode Union Fields
=========================================

Overview
========

The Linux VFS inode structure (``struct inode``) contains several union fields
to optimize memory usage. This document explains the purpose and functionality
of these unions.

The i_dentry/i_rcu Union
========================

Location: ``include/linux/fs.h``

.. code-block:: c

    union {
        struct hlist_head   i_dentry;
        struct rcu_head     i_rcu;
    };

Functionality
-------------

This union contains two fields that serve different purposes during different
phases of an inode's lifecycle:

i_dentry (Active Inode Phase)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

During the normal lifetime of an inode, the ``i_dentry`` field is used:

* **Purpose**: Maintains a list of all directory entries (dentries) that 
  reference this inode.

* **Why Multiple Dentries?**: A single inode can be referenced by multiple 
  dentries, which happens in the following cases:
  
  - Hard links: Multiple directory entries pointing to the same file
  - Directory entries in different mount namespaces
  - Bind mounts referencing the same underlying inode

* **Data Structure**: ``struct hlist_head`` is a hash list head that serves
  as the anchor point for a linked list of dentries.

* **Usage Example**: When the kernel needs to invalidate all cached dentries
  for an inode (e.g., during file deletion), it traverses this list.

i_rcu (Inode Destruction Phase)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When an inode is being destroyed, the ``i_rcu`` field is used:

* **Purpose**: Enables safe, delayed freeing of the inode structure using
  the RCU (Read-Copy-Update) mechanism.

* **Why RCU?**: In the Linux kernel, some code paths access inodes without
  holding locks, relying instead on RCU read-side critical sections. To
  prevent use-after-free bugs, the inode cannot be immediately freed when
  its reference count drops to zero. Instead, it must wait until all
  potential RCU readers have completed.

* **Data Structure**: ``struct rcu_head`` contains the callback information
  needed for RCU-delayed reclamation.

* **Usage Flow**:
  
  1. When an inode's reference count reaches zero, the kernel initiates
     destruction
  2. The inode is removed from all lists and its ``i_dentry`` field is no
     longer needed
  3. The same memory location is repurposed to store the ``i_rcu`` field
  4. ``call_rcu()`` is invoked to schedule delayed freeing
  5. After an RCU grace period, the callback frees the inode memory

Memory Optimization
-------------------

The union allows these two fields to share the same memory location because:

1. **Mutual Exclusion**: An inode never needs both fields simultaneously:
   
   - While active, it needs ``i_dentry`` to track directory entries
   - During destruction, it no longer has dentries and needs ``i_rcu`` for
     safe memory reclamation

2. **Space Efficiency**: Both fields have similar size requirements:
   
   - ``struct hlist_head``: typically 8 bytes (single pointer)
   - ``struct rcu_head``: typically 16 bytes (two pointers)
   
   By using a union, we save memory that would otherwise be wasted if both
   fields existed separately.

Code References
---------------

Key functions that interact with this union:

* ``fs/inode.c:i_callback()`` - RCU callback that uses ``i_rcu``
* ``fs/inode.c:destroy_inode()`` - Initiates RCU-delayed freeing
* ``fs/dcache.c`` - Various functions that traverse ``i_dentry`` lists

See Also
--------

* Documentation/RCU/whatisRCU.rst - Understanding RCU
* Documentation/filesystems/vfs.rst - VFS overview
* Documentation/filesystems/path-lookup.rst - Dentry and inode relationships
