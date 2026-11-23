import 'package:flutter/material.dart';

import 'ui/workbench_page.dart';

class PromapApp extends StatelessWidget {
  const PromapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'promap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
      ),
      home: const WorkbenchPage(),
    );
  }
}
