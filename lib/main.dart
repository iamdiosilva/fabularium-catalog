import 'package:flutter/material.dart';

import 'pages/catalog_page.dart';

void main() {
  runApp(
    const FabulariumApp(),
  );
}

class FabulariumApp extends StatelessWidget {
  const FabulariumApp({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fabularium',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
      ),
      home: const CatalogPage(
        fabulariumPath:  r'D:\Fabularium',
      ),
    );
  }
}