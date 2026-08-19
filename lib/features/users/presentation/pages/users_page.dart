import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../register/presentation/pages/register_page.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../core/errors/app_error.dart';

class RecentUserHighlightNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setHighlight(String? username) => state = username;
}

final recentUserHighlightProvider = NotifierProvider<RecentUserHighlightNotifier, String?>(
  RecentUserHighlightNotifier.new,
);

final allUsersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('users')
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => {...doc.data(), 'uid': doc.id})
          .where((user) {
            final isDeleted = user['isDeleted'] == true;
            final isInternalAccount = user['isInternalAccount'] == true;
            final isHidden = user['isHidden'] == true;

            // Always hide hard-deleted users and internal/hidden accounts
            if (isDeleted || isInternalAccount || isHidden) return false;

            return true;
          })
          .toList());
});

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(allUsersProvider);
    final highlightUsername = ref.watch(recentUserHighlightProvider);

    if (highlightUsername != null) {
      Future.delayed(const Duration(seconds: 5), () {
        if (ref.read(recentUserHighlightProvider) == highlightUsername) {
          ref.read(recentUserHighlightProvider.notifier).setHighlight(null);
        }
      });
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Staff Management',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterPage(standalone: true)),
                    );
                  },
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text(
                    'New User',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004B93),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: staffAsync.when(
                data: (staffList) {
                  if (staffList.isEmpty) return const Center(child: Text('No staff accounts yet.'));

                  // Sort: active users first, then deactivated
                  final sorted = [...staffList];
                  sorted.sort((a, b) {
                    final aStatus = (a['status'] ?? 'active').toString().toLowerCase();
                    final bStatus = (b['status'] ?? 'active').toString().toLowerCase();
                    final aActive = aStatus == 'active';
                    final bActive = bStatus == 'active';
                    if (aActive && !bActive) return -1;
                    if (!aActive && bActive) return 1;
                    return 0;
                  });

                  return ListView.builder(
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final s = sorted[index];
                      final status = (s['status'] ?? 'active').toString().toLowerCase();
                      final isActive = status == 'active';
                      final isDeactivated = status == 'deactivated' || status == 'disabled' || status == 'inactive';
                      final uName = (s['username'] ?? '').toString().toUpperCase();
                      final isHighlighted = (highlightUsername != null && uName == highlightUsername);

                      return Opacity(
                        opacity: isDeactivated ? 0.6 : 1.0,
                        child: Card(
                          color: isHighlighted
                              ? const Color(0xFFE2E8F0)
                              : isDeactivated
                                  ? const Color(0xFFFFF8F0)
                                  : Colors.white,
                          elevation: isHighlighted ? 3 : 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isHighlighted
                                  ? const Color(0xFF64748B)
                                  : isDeactivated
                                      ? Colors.orange.shade200
                                      : Colors.grey.shade200,
                              width: isHighlighted ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              if (isHighlighted)
                                Container(
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF64748B),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(10.5),
                                      topRight: Radius.circular(10.5),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.new_releases, color: Colors.white, size: 13),
                                      SizedBox(width: 6),
                                      Text(
                                        'NEWLY CREATED USER',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (isDeactivated && !isHighlighted)
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade700,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(10.5),
                                      topRight: Radius.circular(10.5),
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.block, color: Colors.white, size: 13),
                                      SizedBox(width: 6),
                                      Text(
                                        'DEACTIVATED ACCOUNT',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isActive ? Colors.green.shade100 : Colors.orange.shade100,
                                  child: Icon(
                                    isActive ? Icons.person : Icons.person_off,
                                    color: isActive ? Colors.green : Colors.orange.shade700,
                                  ),
                                ),
                                title: Text(
                                  s['name'] ?? 'Unknown',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDeactivated ? Colors.grey.shade600 : null,
                                    decoration: isDeactivated ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                subtitle: Text('Role: ${s['role'] == 'admin' ? 'Admin' : 'User'} • Username: ${s['username']}'),
                                onTap: () => _showUserDetails(context, s),
                                trailing: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isActive ? 'Active' : 'Deactivated',
                                        style: TextStyle(
                                          color: isActive ? Colors.green : Colors.orange.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _DeactivationSwitch(
                                        isActive: isActive,
                                        userUid: s['uid'],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserDetails(BuildContext context, Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _UserDetailsModal(user: user);
      },
    );
  }
}

class _UserDetailsModal extends ConsumerStatefulWidget {
  final Map<String, dynamic> user;

  const _UserDetailsModal({required this.user});

  @override
  ConsumerState<_UserDetailsModal> createState() => _UserDetailsModalState();
}

class _UserDetailsModalState extends ConsumerState<_UserDetailsModal> {
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  late String _selectedRole;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSaving = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user['name'] ?? '');
    _phoneController = TextEditingController(text: widget.user['phone'] ?? '');
    _selectedRole = widget.user['role'] ?? 'staff';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updateUser() async {
    final newPass = _passwordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();

    if (newPass.isNotEmpty) {
      if (newPass.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password must be at least 6 characters long.'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (newPass != confirmPass) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Passwords do not match. Please verify.'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _statusMessage = newPass.isNotEmpty ? 'Updating user password...' : 'Updating user details...';
    });

    try {
      final targetUid = widget.user['uid'] as String;

      // 1. If password is provided, update via admin auth helper
      if (newPass.isNotEmpty) {
        final authController = ref.read(authControllerProvider);
        await authController.adminUpdateUserPassword(
          targetUid: targetUid,
          newPassword: newPass,
        );
      }

      // 2. Update user profile fields (name, phone, role)
      final updateData = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': _selectedRole,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('users').doc(targetUid).update(updateData);

      if (mounted) {
        _passwordController.clear();
        _confirmPasswordController.clear();
        setState(() {
          _obscurePassword = true;
          _obscureConfirmPassword = true;
        });

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newPass.isNotEmpty
                  ? '✓ Password and user details updated successfully.'
                  : '✓ User details updated successfully.',
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = AppError.map(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User?'),
        content: Text('Are you sure you want to delete ${widget.user['name']}? This user will be deactivated and removed from active staff lists.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isSaving = true;
        _statusMessage = 'Deleting user account...';
      });
      try {
        final authController = ref.read(authControllerProvider);
        await authController.deleteUserAccount(targetUid: widget.user['uid']);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ User deleted successfully'),
              backgroundColor: Color(0xFF16A34A),
            ),
          );
        }
      } catch (e) {
        final errorMsg = AppError.map(e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isSaving = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = widget.user['createdAt'] as Timestamp?;
    final dateStr = createdAt != null ? createdAt.toDate().toString() : 'N/A';
    final username = (widget.user['username'] ?? 'N/A').toString();
    final email = (widget.user['email'] ?? '').toString().isNotEmpty
        ? widget.user['email'].toString()
        : '${username.toLowerCase()}@internal.shifa.app';

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'User Details & Security',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Username: $username',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Auth Email: $email',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text('Created: $dateStr', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              enabled: !_isSaving,
              decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              enabled: !_isSaving,
              decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: (['staff', 'admin'].contains(_selectedRole)) ? _selectedRole : 'staff',
              decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'staff', child: Text('User')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: _isSaving ? null : (value) {
                if (value != null) setState(() => _selectedRole = value);
              },
            ),
            const SizedBox(height: 20),

            // ─── Manual Password Update Section ───
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF004B93)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'CHANGE PASSWORD (OPTIONAL)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF004B93),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Leave blank to keep the current password.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    enabled: !_isSaving,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      hintText: 'Minimum 6 characters',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    enabled: !_isSaving,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      hintText: 'Re-enter new password',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirmPassword ? 'Show password' : 'Hide password',
                        icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, size: 20),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_isSaving) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF), // blue-50
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF004B93)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: Color(0xFF1E40AF),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ─── Modal Actions (Overflow Safe) ───
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                TextButton.icon(
                  onPressed: _isSaving ? null : _deleteUser,
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Delete User', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _updateUser,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Updating...' : 'Save Changes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004B93),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Toggle switch with confirmation dialog for deactivating/reactivating users.
class _DeactivationSwitch extends ConsumerStatefulWidget {
  final bool isActive;
  final String userUid;

  const _DeactivationSwitch({required this.isActive, required this.userUid});

  @override
  ConsumerState<_DeactivationSwitch> createState() => _DeactivationSwitchState();
}

class _DeactivationSwitchState extends ConsumerState<_DeactivationSwitch> {
  bool _isProcessing = false;

  Future<void> _handleToggle(bool newValue) async {
    final action = newValue ? 'reactivate' : 'deactivate';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${action[0].toUpperCase()}${action.substring(1)} Account?'),
        content: Text(
          newValue
              ? 'This will restore the account. The user will be able to log in again.'
              : 'This will deactivate the account and log the user out from ALL devices immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newValue ? Colors.green : Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            child: Text(newValue ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isProcessing = true);

    try {
      final authController = ref.read(authControllerProvider);
      if (newValue) {
        await authController.reactivateUser(targetUid: widget.userUid);
      } else {
        await authController.deactivateUser(targetUid: widget.userUid);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newValue
                ? '✓ Account reactivated successfully'
                : '✓ Account deactivated — user logged out from all devices'),
            backgroundColor: newValue ? Colors.green : Colors.orange.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = AppError.map(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isProcessing) {
      return const SizedBox(
        width: 48,
        height: 24,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Switch(
      value: widget.isActive,
      activeThumbColor: Colors.green,
      activeTrackColor: Colors.green.shade200,
      inactiveThumbColor: Colors.orange.shade700,
      inactiveTrackColor: Colors.orange.shade100,
      onChanged: _handleToggle,
    );
  }
}
