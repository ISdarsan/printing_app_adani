package com.adani.canteen_adani

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Bluetooth (SPP/RFCOMM) bridge for ESC/POS thermal printers.
 *
 * Replaces the blue_thermal_printer connection layer, which
 *  - never returned from getBondedDevices() on Android 12+ (it waits for
 *    ACCESS_FINE_LOCATION, which this app does not declare for API 31+),
 *  - reported "connected" after the printer was switched off, and
 *  - swallowed write errors, so failed prints looked successful.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "thermal_printer"
    private val permissionRequestCode = 7301
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    // All socket work happens on one background thread, in order.
    private val io = Executors.newSingleThreadExecutor()

    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var output: OutputStream? = null
    private var pendingPermission: MethodChannel.Result? = null

    private val adapter: BluetoothAdapter?
        get() = getSystemService(BluetoothManager::class.java)?.adapter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(adapter != null)
                    "isOn" -> result.success(adapter?.isEnabled == true)
                    "ensurePermission" -> ensurePermission(result)
                    "getBondedDevices" -> getBondedDevices(result)
                    "isConnected" -> result.success(
                        socket?.isConnected == true && output != null
                    )
                    "connect" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) {
                            result.error("invalid_argument", "Printer address is required", null)
                        } else {
                            connect(address, result)
                        }
                    }
                    "disconnect" -> {
                        io.execute {
                            closeSocket()
                            runOnUiThread { result.success(true) }
                        }
                    }
                    "write" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("invalid_argument", "bytes are required", null)
                        } else {
                            write(bytes, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        io.execute { closeSocket() }
        io.shutdown()
        super.onDestroy()
    }

    // ── Permissions ─────────────────────────────────────────────

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun ensurePermission(result: MethodChannel.Result) {
        if (hasConnectPermission()) {
            result.success(true)
            return
        }
        // A second request while one is open would orphan the first result.
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), permissionRequestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermission?.success(granted)
            pendingPermission = null
        }
    }

    // ── Devices ─────────────────────────────────────────────────

    private fun getBondedDevices(result: MethodChannel.Result) {
        val bt = adapter
        if (bt == null) {
            result.error("no_bluetooth", "Bluetooth is not available on this device", null)
            return
        }
        if (!hasConnectPermission()) {
            result.error("no_permission", "Bluetooth permission not granted", null)
            return
        }
        try {
            val list = bt.bondedDevices.orEmpty().map {
                mapOf("name" to (it.name ?: "Unknown"), "address" to it.address)
            }
            result.success(list)
        } catch (e: SecurityException) {
            result.error("no_permission", e.message, null)
        }
    }

    // ── Connection ──────────────────────────────────────────────

    private fun connect(address: String, result: MethodChannel.Result) {
        io.execute {
            closeSocket()
            val bt = adapter
            if (bt == null || !bt.isEnabled) {
                runOnUiThread { result.error("bluetooth_off", "Bluetooth is turned off", null) }
                return@execute
            }
            if (!hasConnectPermission()) {
                runOnUiThread { result.error("no_permission", "Bluetooth permission not granted", null) }
                return@execute
            }
            try {
                val device = bt.getRemoteDevice(address)
                bt.cancelDiscovery()
                val s = openSocket(device)
                socket = s
                output = s.outputStream
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                closeSocket()
                runOnUiThread {
                    result.error("connect_error", e.message ?: "Could not connect", null)
                }
            }
        }
    }

    /** Tries the standard secure SPP socket, then the insecure one, then the
     *  reflection channel-1 socket that many cheap printers need. */
    private fun openSocket(device: android.bluetooth.BluetoothDevice): BluetoothSocket {
        var last: Exception? = null
        val factories = listOf<() -> BluetoothSocket>(
            { device.createRfcommSocketToServiceRecord(sppUuid) },
            { device.createInsecureRfcommSocketToServiceRecord(sppUuid) },
            {
                @Suppress("UNCHECKED_CAST")
                device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                    .invoke(device, 1) as BluetoothSocket
            }
        )
        for (make in factories) {
            var candidate: BluetoothSocket? = null
            try {
                candidate = make()
                candidate.connect()
                return candidate
            } catch (e: Exception) {
                last = e
                try { candidate?.close() } catch (_: Exception) {}
            }
        }
        throw last ?: IllegalStateException("Could not open printer socket")
    }

    private fun closeSocket() {
        try { output?.close() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        output = null
        socket = null
    }

    // ── Printing ────────────────────────────────────────────────

    private fun write(bytes: ByteArray, result: MethodChannel.Result) {
        io.execute {
            val out = output
            if (out == null || socket?.isConnected != true) {
                runOnUiThread { result.error("not_connected", "Printer is not connected", null) }
                return@execute
            }
            try {
                // Small chunks: cheap printers have tiny buffers and drop
                // data when a whole receipt is pushed at once.
                var offset = 0
                while (offset < bytes.size) {
                    val end = minOf(offset + 512, bytes.size)
                    out.write(bytes, offset, end - offset)
                    out.flush()
                    offset = end
                    if (offset < bytes.size) Thread.sleep(20)
                }
                // Let the printer drain its buffer before the caller moves on.
                Thread.sleep(150)
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                closeSocket()
                runOnUiThread {
                    result.error("write_error", e.message ?: "Write to printer failed", null)
                }
            }
        }
    }
}
