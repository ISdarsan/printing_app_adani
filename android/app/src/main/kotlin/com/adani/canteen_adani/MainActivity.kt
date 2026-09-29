package com.adani.canteen_adani

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val printerPairingChannel = "printer_pairing"
    private var bluetoothAdapter: BluetoothAdapter? = null
    private val discoveredDevices = linkedMapOf<String, String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, printerPairingChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAvailablePrinters" -> {
                        result.success(getAvailablePrinters())
                    }
                    "pairDevice" -> {
                        val address = call.argument<String>("address")
                        if (address.isNullOrBlank()) {
                            result.error("invalid_argument", "Printer address is required", null)
                            return@setMethodCallHandler
                        }
                        val device = bluetoothAdapter?.getRemoteDevice(address)
                        if (device == null) {
                            result.error("device_not_found", "Printer not found", null)
                            return@setMethodCallHandler
                        }
                        val paired = device.createBond()
                        result.success(paired)
                    }
                    else -> result.notImplemented()
                }
            }

        val bluetoothManager = getSystemService(android.bluetooth.BluetoothManager::class.java)
        bluetoothAdapter = bluetoothManager?.adapter

        if (bluetoothAdapter != null) {
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            registerReceiver(bluetoothReceiver, filter)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(bluetoothReceiver)
        } catch (_: IllegalArgumentException) {
        }
        super.onDestroy()
    }

    private fun getAvailablePrinters(): List<Map<String, Any?>> {
        val adapter = bluetoothAdapter ?: return emptyList()
        val set = linkedMapOf<String, Map<String, Any?>>()

        adapter.bondedDevices?.forEach { device ->
            set[device.address] = mapOf(
                "name" to (device.name ?: "Printer"),
                "address" to device.address,
                "paired" to true,
            )
        }

        discoveredDevices.forEach { (address, name) ->
            set.putIfAbsent(address, mapOf(
                "name" to name,
                "address" to address,
                "paired" to false,
            ))
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val required = arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
            if (required.any { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }) {
                return set.values.toList()
            }
        } else {
            val required = arrayOf(
                Manifest.permission.ACCESS_COARSE_LOCATION,
                Manifest.permission.ACCESS_FINE_LOCATION,
            )
            if (required.any { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }) {
                return set.values.toList()
            }
        }

        if (!adapter.isDiscovering) {
            adapter.startDiscovery()
        }

        return set.values.toList()
    }

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    val address = device?.address ?: return
                    val name = device.name ?: "Printer"
                    if (address.isNotBlank()) {
                        discoveredDevices[address] = name
                    }
                }
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    val state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                    if (device != null && state == BluetoothDevice.BOND_BONDED) {
                        discoveredDevices.remove(device.address)
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    // no-op, discovery is restarted on demand by the app
                }
            }
        }
    }
}
