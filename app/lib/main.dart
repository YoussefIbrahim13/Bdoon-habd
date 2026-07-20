import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/splash_view.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'state/friendship_state.dart';
import 'state/game_state.dart';
import 'theme/app_theme.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const BedoonHabdApp());
}

class BedoonHabdApp extends StatelessWidget {
  const BedoonHabdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => ApiService()),
        ChangeNotifierProvider(create: (_) => GameState()),
        // Session restore kicks off immediately: by the time the splash
        // hands over to the gateway, a persisted sign-in is already live.
        ChangeNotifierProvider(create: (_) => AuthService()..restoreSession()),
        // Friends system reads the JWT from AuthService (provided above).
        ChangeNotifierProvider(
          create: (ctx) => FriendshipState(auth: ctx.read<AuthService>()),
        ),
      ],
      child: MaterialApp(
        title: 'بدون هبد!',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        // Arabic-first UI: force RTL everywhere.
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: const SplashView(),
      ),
    );
  }
}
