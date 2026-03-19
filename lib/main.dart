import 'package:flutter/material.dart';

import 'SSHController.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SSH Client',
      debugShowCheckedModeBanner: false,
      home: const SSHScreen(),
    );
  }
}

class SSHScreen extends StatefulWidget {
  const SSHScreen({super.key});

  @override
  State<SSHScreen> createState() => _SSHScreenState();
}

class _SSHScreenState extends State<SSHScreen> {
  final controller = SSHController();
  final ipController = TextEditingController();
  final userController = TextEditingController();
  final passController = TextEditingController();
  final commandController = TextEditingController();

  String output = "";

  void ejecutarComando() async {
    final result = await controller.ejecutarComando(
      ip: ipController.text,
      usuario: userController.text,
      password: passController.text,
      comando: commandController.text,
    );

    setState(() {
      output = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SSH Executor"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: "IP",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: userController,
              decoration: const InputDecoration(
                labelText: "Usuario",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Contraseña",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: commandController,
              decoration: const InputDecoration(
                labelText: "Comando",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: ejecutarComando,
              child: const Text("Ejecutar"),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                ),
                child: SingleChildScrollView(
                  child: Text(output),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}