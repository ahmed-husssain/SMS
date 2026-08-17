import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/plan_expiration_provider.dart';
import '../../features/dashboard/presentation/widgets/notifications_modal.dart';

class MainLayout extends ConsumerWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(userProfileProvider.select((v) => v.value?['role'] ?? 'staff'));
    final expiringCount = ref.watch(expiringPlansProvider).value?.length ?? 0;

    // Navigation items based on role
    final navItems = <_NavItem>[
      const _NavItem(icon: Icons.home, label: 'Home', path: '/dashboard'),
      const _NavItem(icon: Icons.person_add, label: 'Register', path: '/register'),
      const _NavItem(icon: Icons.folder, label: 'Records', path: '/records'),
      const _NavItem(icon: Icons.receipt_long, label: 'Invoices', path: '/invoices'),
      const _NavItem(icon: Icons.attach_money, label: 'Finance', path: '/finances'),
      if (role == 'admin') const _NavItem(icon: Icons.people, label: 'Users', path: '/users'),
    ];

    // Determine current index based on location
    final location = GoRouterState.of(context).matchedLocation;
    int currentIndex = navItems.indexWhere((item) => location.startsWith(item.path));
    if (currentIndex == -1) currentIndex = 0; // Default to dashboard

    void onNavItemSelected(int index) {
      context.go(navItems[index].path);
    }

    void handleLogout() {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(authControllerProvider).logout();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Logout', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black87,
        title: Image.asset(
          'assets/Shifa_Logo-BG.png',
          height: 52,
          fit: BoxFit.contain,
        ),
        actions: [
          _PulsingNotificationBell(
            count: expiringCount,
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const NotificationsModal(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            tooltip: 'Logout',
            onPressed: handleLogout,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0056B3),
              Color(0xFF003D7A),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            indicatorColor: Colors.white.withOpacity(0.25),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: Colors.white, size: 24);
              }
              return const IconThemeData(color: Colors.white70, size: 24);
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white);
              }
              return const TextStyle(fontSize: 11, color: Colors.white70);
            }),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedIndex: currentIndex,
            onDestinationSelected: onNavItemSelected,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined, color: Colors.white70),
                selectedIcon: Icon(Icons.home, color: Colors.white),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_add_outlined, color: Colors.white70),
                selectedIcon: Icon(Icons.person_add, color: Colors.white),
                label: 'Register',
              ),
              const NavigationDestination(
                icon: Icon(Icons.folder_outlined, color: Colors.white70),
                selectedIcon: Icon(Icons.folder, color: Colors.white),
                label: 'Records',
              ),
              const NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined, color: Colors.white70),
                selectedIcon: Icon(Icons.receipt_long, color: Colors.white),
                label: 'Invoices',
              ),
              const NavigationDestination(
                icon: Icon(Icons.attach_money, color: Colors.white70),
                selectedIcon: Icon(Icons.attach_money, color: Colors.white),
                label: 'Finance',
              ),
              if (role == 'admin')
                const NavigationDestination(
                  icon: Icon(Icons.people_outline, color: Colors.white70),
                  selectedIcon: Icon(Icons.people, color: Colors.white),
                  label: 'Users',
                ),
            ],
          ),
        ),
      ),
      body: child,
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String path;

  const _NavItem({required this.icon, required this.label, required this.path});
}

class _PulsingNotificationBell extends StatefulWidget {
  final int count;
  final VoidCallback onTap;

  const _PulsingNotificationBell({required this.count, required this.onTap});

  @override
  State<_PulsingNotificationBell> createState() => _PulsingNotificationBellState();
}

class _PulsingNotificationBellState extends State<_PulsingNotificationBell> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Color(0xFF1565C0), size: 24),
          tooltip: 'Notifications',
          onPressed: widget.onTap,
        ),
        if (widget.count > 0)
          Positioned(
            top: 8,
            right: 8,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Text(
                  '${widget.count}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

