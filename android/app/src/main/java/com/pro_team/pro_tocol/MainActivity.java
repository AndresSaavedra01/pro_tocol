package com.pro_team.pro_tocol;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import com.pro_team.pro_tocol.service.SSHService;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends FlutterActivity {

    private static final String CHANNEL = "ssh_channel";

    // 🧵 Hilo en segundo plano (MUY IMPORTANTE)
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                CHANNEL
        ).setMethodCallHandler((call, result) -> {

            if (call.method.equals("executeSSH")) {

                String ip = call.argument("ip");
                String usuario = call.argument("usuario");
                String password = call.argument("password");
                String comando = call.argument("comando");

                // 🚀 Ejecutar en background
                executor.execute(() -> {

                    try {
                        SSHService service = new SSHService();

                        String output = service.ejecutarComando(
                                ip,
                                usuario,
                                password,
                                comando
                        );

                        // 🔁 Devolver resultado al hilo principal
                        runOnUiThread(() -> result.success(output));

                    } catch (Exception e) {
                        runOnUiThread(() ->
                                result.error("SSH_ERROR", e.getMessage(), null)
                        );
                    }
                });

            } else {
                result.notImplemented();
            }
        });
    }
}