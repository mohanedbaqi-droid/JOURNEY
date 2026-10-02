import SwiftUI

struct ManageDevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var devices: DeviceStore
    @EnvironmentObject private var proximity: ProximityMonitor
    @State private var showingAdd = false
    @State private var discoveryError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("إضافة من البلوتوث") {
                    if proximity.discoveredDevices.isEmpty {
                        HStack {
                            ProgressView().opacity(proximity.isScanning ? 1 : 0)
                            Text(proximity.isScanning ? "جاري البحث عن البوردات…" : "اضغط بحث للعثور على البوردات")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(proximity.discoveredDevices) { found in
                            Button {
                                addDiscovered(found)
                            } label: {
                                HStack {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                    VStack(alignment: .leading) {
                                        Text(found.deviceID).foregroundStyle(.primary)
                                        Text("\(found.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if devices.devices.contains(where: { $0.deviceID == found.deviceID }) {
                                        Text("مضاف").font(.caption).foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "plus.circle")
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        proximity.start()
                    } label: {
                        Label("بحث بالبلوتوث", systemImage: "arrow.clockwise")
                    }

                    if let discoveryError {
                        Text(discoveryError).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("الأجهزة المحفوظة") {
                    ForEach(devices.devices) { device in
                        Button {
                            devices.selectedID = device.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name).foregroundStyle(.primary)
                                    Text(device.deviceID).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if device.id == devices.selectedID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    .onDelete(perform: devices.delete)
                }
            }
            .navigationTitle("الأجهزة")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("تم") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddDeviceView()
                    .environmentObject(devices)
            }
            .onAppear { proximity.start() }
            .onDisappear { proximity.stop() }
        }
    }

    private func addDiscovered(_ found: ProximityMonitor.DiscoveredDevice) {
        if let existing = devices.devices.first(where: { $0.deviceID == found.deviceID }) {
            devices.selectedID = existing.id
            dismiss()
            return
        }

        if let error = devices.add(name: found.deviceID, deviceID: found.deviceID) {
            discoveryError = error
        } else {
            dismiss()
        }
    }
}

private struct AddDeviceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var devices: DeviceStore
    @State private var name = ""
    @State private var deviceID = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("معلومات الجهاز") {
                    TextField("مثال: جورني أبو سيف", text: $name)
                    TextField("مثال: journey-02", text: $deviceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("معرّف الجهاز لازم يطابق DEVICE_ID المكتوب داخل config.h لذلك البورد.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("إضافة جهاز")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("إضافة") {
                        if let error = devices.add(name: name, deviceID: deviceID) {
                            errorText = error
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
