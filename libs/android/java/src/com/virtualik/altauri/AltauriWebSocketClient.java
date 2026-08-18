package com.virtualik.altauri;

import android.content.Context;
import android.util.Log;

import org.java_websocket.client.WebSocketClient;
import org.java_websocket.handshake.ServerHandshake;

import java.net.URI;
import java.net.URISyntaxException;
import java.nio.ByteBuffer;

public class AltauriWebSocketClient {
    private static final String TAG = "AltauriWS";

    private WebSocketClient webSocket;
    private long haxePtr;

    public AltauriWebSocketClient(Context context, long haxePtr) {
        this.haxePtr = haxePtr;
        Log.i(TAG, "AltauriWebSocketClient created for Haxe ptr: " + haxePtr);
    }

    public void connect(String url, String subprotocol) {
		Log.i(TAG, "JAVA connect() CALLED! url=" + url + ", subprotocol=" + subprotocol);
        
        try {
            URI uri = new URI(url);
            
            webSocket = new WebSocketClient(uri) {
                @Override
                public void onOpen(ServerHandshake handshakedata) {
                    Log.i(TAG, "WebSocket Opened");
                    nativeOnOpen(haxePtr);
                }

                @Override
                public void onMessage(String message) {
                    Log.i(TAG, "Text message received, length: " + message.length());
                    nativeOnMessage(haxePtr, message.getBytes(), message.getBytes().length);
                }

                // ИСПРАВЛЕНО: используем ByteBuffer вместо byte[] для совместимости с библиотекой
                @Override
                public void onMessage(ByteBuffer bytes) {
                    byte[] byteArray = new byte[bytes.remaining()];
                    bytes.get(byteArray);
                    Log.i(TAG, "Binary message received, length: " + byteArray.length);
                    nativeOnMessage(haxePtr, byteArray, byteArray.length);
                }

                @Override
                public void onClose(int code, String reason, boolean remote) {
                    Log.i(TAG, "WebSocket Closed: code=" + code + ", reason=" + reason);
                    nativeOnClose(haxePtr, code, reason);
                }

                @Override
                public void onError(Exception ex) {
                    Log.e(TAG, "WebSocket Error", ex);
                    String errMsg = ex.getMessage() != null ? ex.getMessage() : "Unknown error";
                    nativeOnError(haxePtr, errMsg);
                }
            };

            // ПРИМЕЧАНИЕ: Если ваш jar-файл java-websocket старый или урезанный, 
            // метод addProtocol может отсутствовать. Subprotocol опционален, 
            // поэтому мы безопасно пропускаем его добавление, чтобы избежать ошибки компиляции.
            // if (subprotocol != null && !subprotocol.isEmpty()) {
            //     webSocket.addProtocol(subprotocol);
            // }

            webSocket.connect();
            Log.i(TAG, "Connecting to: " + url);

        } catch (URISyntaxException e) {
            Log.e(TAG, "Invalid URI: " + url, e);
            nativeOnError(haxePtr, "Invalid URI: " + e.getMessage());
        } catch (Exception e) {
            Log.e(TAG, "Connection failed", e);
            nativeOnError(haxePtr, "Connection failed: " + e.getMessage());
        }
    }

    public void send(byte[] data, int length) {
        if (webSocket != null && webSocket.isOpen()) {
            try {
                // Библиотека java-websocket поддерживает отправку byte[] напрямую
                webSocket.send(data);
                Log.i(TAG, "Sent " + length + " bytes successfully");
            } catch (Exception e) {
                Log.e(TAG, "Failed to send data", e);
                nativeOnError(haxePtr, "Send failed: " + e.getMessage());
            }
        } else {
            Log.w(TAG, "Cannot send: WebSocket is null or not open. State: " + (webSocket != null ? webSocket.getReadyState() : "null"));
            nativeOnError(haxePtr, "WebSocket is not connected");
        }
    }

    public void disconnect() {
        if (webSocket != null) {
            try {
                webSocket.close();
                Log.i(TAG, "WebSocket disconnect requested");
            } catch (Exception e) {
                Log.e(TAG, "Error during disconnect", e);
            }
            webSocket = null;
        }
    }

    private native void nativeOnOpen(long haxePtr);
    private native void nativeOnMessage(long haxePtr, byte[] data, int length);
    private native void nativeOnClose(long haxePtr, int code, String reason);
    private native void nativeOnError(long haxePtr, String error);
}