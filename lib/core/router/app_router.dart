import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/providers/auth_provider.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../presentation/main_layout.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';

import '../../features/records/presentation/pages/records_page.dart';
import '../../features/finances/presentation/pages/finances_page.dart';
import '../../features/invoices/presentation/pages/invoices_page.dart';
import '../../features/users/presentation/pages/users_page.dart';

import '../../features/splash/presentation/splash_screen.dart';
import '../../features/patients/presentation/patient_form_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final userProfile = ref.watch(userProfileProvider);
  final splashCompleted = ref.watch(splashCompletedProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isLoggingIn = state.matchedLocation == '/login';
      final isSplash = state.matchedLocation == '/splash';

      if (!splashCompleted) {
        return isSplash ? null : '/splash';
      }

      if (authState.isLoading || userProfile.isLoading) {
        return '/splash';
      }

      if (authState.hasError || userProfile.hasError) {
        // Sign out to clear bad state and prevent infinite redirect loops
        ref.read(firebaseAuthProvider).signOut();
        return '/login';
      }

      final user = authState.value;

      if (user == null) {
        return isLoggingIn ? null : '/login';
      }

      final profile = userProfile.value;
      if (profile == null) {
        if (userProfile.hasValue) {
          // Profile document doesn't exist in Firestore, sign out
          ref.read(firebaseAuthProvider).signOut();
          return '/login';
        }
        return '/splash';
      }

      // Check if the account has been deactivated (works across all devices
      // because userProfileProvider is a real-time Firestore stream)
      final status = (profile['status'] ?? 'active').toString().toLowerCase();
      if (status == 'deactivated' || status == 'disabled' || status == 'inactive') {
        ref.read(firebaseAuthProvider).signOut();
        return '/login';
      }

      final role = profile['role']; 

      if (isLoggingIn || state.matchedLocation == '/' || state.matchedLocation == '/splash') {
         return '/dashboard';
      }

      // Role-based protection
      if (role == 'staff') {
        final loc = state.matchedLocation;
        if (loc.startsWith('/users')) {
          return '/dashboard';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return MainLayout(child: child);
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/register',
            builder: (context, state) => const PatientFormScreen(),
          ),
          GoRoute(
            path: '/records',
            builder: (context, state) => const RecordsPage(),
          ),
          GoRoute(
            path: '/finances',
            builder: (context, state) => const FinancesPage(),
          ),
          GoRoute(
            path: '/invoices',
            builder: (context, state) => const InvoicesPage(),
          ),
          GoRoute(
            path: '/users',
            builder: (context, state) => const UsersPage(),
          ),
        ],
      ),
    ],
  );
});
