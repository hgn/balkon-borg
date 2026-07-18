import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/services/mqtt_service.dart';
import 'src/state/app_state.dart';
import 'src/state/settings.dart';
import 'src/ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  runApp(BalkonBorgApp(settings: settings));
}

class BalkonBorgApp extends StatelessWidget {
  const BalkonBorgApp({super.key, required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(
          create: (_) => AppState(MqttService(), settings)..connect(),
        ),
      ],
      child: MaterialApp(
        title: 'Balkon-Borg',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.tealAccent,
            brightness: Brightness.dark,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
