import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/platform/platform_providers.dart';
import 'storage/storage_service.dart';
import 'ui/screens/screens.dart';
import 'ui/theme/app_theme.dart';
import 'ui/utils/desktop_window_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Apply desktop window constraints (no-op on mobile).
  DesktopWindowConfig.apply();

  // Initialise Hive storage.
  final appDir = await getApplicationDocumentsDirectory();
  await StorageService.init(path: '${appDir.path}/swiftdrop_data');

  runApp(const ProviderScope(child: SwiftDropApp()));
}

/// Root widget — applies the dark theme and hosts the shell navigation.
class SwiftDropApp extends StatelessWidget {
  const SwiftDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwiftDrop',
      debugShowCheckedModeBanner: false,
      theme: SwiftDropTheme.darkTheme,
      home: Platform.isAndroid ? const _PermissionGateWrapper() : const AppShell(),
    );
  }
}

/// Wrapper that shows [PermissionGateScreen] until all required
/// Android permissions are granted, then switches to [AppShell].
class _PermissionGateWrapper extends ConsumerStatefulWidget {
  const _PermissionGateWrapper();

  @override
  ConsumerState<_PermissionGateWrapper> createState() =>
      _PermissionGateWrapperState();
}

class _PermissionGateWrapperState
    extends ConsumerState<_PermissionGateWrapper> {
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(permissionStateProvider.notifier).checkAll();
      final state = ref.read(permissionStateProvider);
      if (state.allGranted && mounted) {
        setState(() => _permissionsGranted = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_permissionsGranted) {
      return const AppShell();
    }

    return PermissionGateScreen(
      onGranted: () {
        if (mounted) setState(() => _permissionsGranted = true);
      },
    );
  }
}

/// Shell with bottom navigation for the three main tabs.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

  static const _screens = <Widget>[
    HomeScreen(),
    TransfersScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Eagerly initialise the lifecycle manager so it starts observing.
    Future.microtask(() {
      ref.read(lifecycleManagerProvider);
      // Check permissions on first launch (Android only).
      ref.read(permissionStateProvider.notifier).checkAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.radar_rounded),
            activeIcon: Icon(Icons.radar_rounded),
            label: 'Devices',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.swap_horiz_rounded),
            activeIcon: Icon(Icons.swap_horiz_rounded),
            label: 'Transfers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            activeIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
