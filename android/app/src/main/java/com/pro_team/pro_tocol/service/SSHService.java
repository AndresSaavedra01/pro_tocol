package com.pro_team.pro_tocol.service;

import com.jcraft.jsch.*;

import java.io.InputStream;

public class SSHService {

    public String ejecutarComando(String ip, String usuario, String password, String comando) {

        StringBuilder output = new StringBuilder();

        Session session = null;
        ChannelExec channel = null;

        try {
            JSch jsch = new JSch();

            // 🔌 Crear sesión
            session = jsch.getSession(usuario, ip, 22);
            session.setPassword(password);

            // 🔥 Evitar error de host key (solo pruebas)
            session.setConfig("StrictHostKeyChecking", "no");

            // 🔐 Conectar
            session.connect(10000); // timeout 10s

            // 🖥️ Ejecutar comando
            channel = (ChannelExec) session.openChannel("exec");
            channel.setCommand(comando);

            // 📥 Streams
            InputStream in = channel.getInputStream();
            InputStream err = channel.getErrStream();

            channel.connect();

            byte[] buffer = new byte[1024];

            // 📥 Leer salida estándar
            while (true) {

                while (in.available() > 0) {
                    int i = in.read(buffer, 0, buffer.length);
                    if (i < 0) break;
                    output.append(new String(buffer, 0, i));
                }

                // 📥 Leer errores
                while (err != null && err.available() > 0) {
                    int i = err.read(buffer, 0, buffer.length);
                    if (i < 0) break;
                    output.append("ERROR: ").append(new String(buffer, 0, i));
                }

                if (channel.isClosed()) {
                    break;
                }

                Thread.sleep(100);
            }

        } catch (Exception e) {
            return "Error SSH: " + e.getMessage();
        } finally {

            // 🔌 Cerrar recursos
            if (channel != null && channel.isConnected()) {
                channel.disconnect();
            }

            if (session != null && session.isConnected()) {
                session.disconnect();
            }
        }

        return output.toString();
    }
}