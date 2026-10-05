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
                Section(JL("إضافة من البلوتوث", "Add via Bluetooth")) {
                    if proximity.discoveredDevices.isEmpty {
                        HStack {
                            ProgressView().opacity(proximity.isScanning ? 1 : 0)
                            Text(proximity.isScanning ? JL("جاري البحث عن البوردات…", "Searching for boards…") : JL("اضغط بحث للعثور على البوردات", "Tap Search to find boards"))
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
                                        Text(JL("مضاف", "Added")).font(.caption).foregroundStyle(.green)
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
                        Label(JL("بحث بالبلوتوث", "Search Bluetooth"), systemImage: "arrow.clockwise")
                    }

                    if let discoveryError {
                        Text(discoveryError).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section(JL("الأجهزة المحفوظة", "Saved devices")) {
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
            .navigationTitle(JL("الأجهزة", "Devices"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(JL("تم", "Done")) { dismiss() }
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
                Section(JL("معلومات الجهاز", "Device details")) {
                    TextField(JL("مثال: جورني أبو سيف", "Example: Abu Saif's Journey"), text: $name)
                    TextField(JL("مثال: journey-02", "Example: journey-02"), text: $deviceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text(JL("معرّف الجهاز لازم يطابق DEVICE_ID المكتوب داخل config.h لذلك البورد.", "The device ID must match DEVICE_ID in that board's config.h."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle(JL("إضافة جهاز", "Add device"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(JL("إلغاء", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(JL("إضافة", "Add")) {
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
