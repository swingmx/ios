import SwiftUI
import os
import AVFoundation

private let logger = Logger(subsystem: "com.swingmusic.app", category: "LoginView")

struct LoginView: View {
    @EnvironmentObject var state: AppState
    @State private var server = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var loading = false
    @State private var error: String?
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image("Logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 72)
                            Text("Swing Music")
                                .font(.title2.weight(.semibold))
                            Text("Sign in to your server")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section("Server") {
                    TextField("https://music.example.com", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Account") {
                    TextField("Username", text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $pass)
                }

                Section {
                    Button {
                        Task { await go() }
                    } label: {
                        HStack {
                            Spacer()
                            if loading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Sign In")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                        .frame(height: 28)
                        .padding(.vertical, 8)
                        .modifier(BlueLiquidGlassBackground())
                    }
                    .buttonStyle(.plain)
                    .disabled(loading || server.isEmpty)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section {
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Connection Error", isPresented: Binding(
                get: { error != nil },
                set: { _ in error = nil }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(error ?? "Unknown error occurred")
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet { payload in
                    Task { await handleQR(payload) }
                }
            }
        }
    }

    private func go() async {
        loading = true
        error = nil
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await state.login(server: trimmed, user: user, pass: pass)
        } catch {
            withAnimation { self.error = error.localizedDescription }
        }
        loading = false
    }

    private func handleQR(_ payload: String) async {
        showScanner = false
        loading = true
        error = nil

        if let auth = parseQRPayload(payload) {
            do {
                if let code = auth.code {
                    try await state.loginWithPairingCode(server: auth.server, code: code)
                } else if let token = auth.token {
                    try await state.loginWithToken(server: auth.server, token: token)
                } else if let user = auth.user, let pass = auth.pass {
                    try await state.login(server: auth.server, user: user, pass: pass)
                }
            } catch {
                self.error = error.localizedDescription
            }
        } else {
            error = "Invalid QR code format. Please ensure it follows SwingMusic's standard."
        }
        loading = false
    }

    private func parseQRPayload(_ payload: String) -> QRAuthPayload? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.components(separatedBy: " ")
        if parts.count == 2, parts[0].contains("://") {
            return QRAuthPayload(server: parts[0], token: nil, user: nil, pass: nil, code: parts[1])
        }
        if let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let server = (json["server"] as? String) ?? (json["base"] as? String)
            return QRAuthPayload(server: server ?? "", token: json["token"] as? String, user: json["username"] as? String, pass: json["password"] as? String, code: nil)
        }
        if let c = URLComponents(string: text) {
            let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") })
            if let s = q["server"] { return QRAuthPayload(server: s, token: q["token"], user: q["username"], pass: q["password"], code: nil) }
        }
        return nil
    }
}

private struct BlueLiquidGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(.blue).interactive(), in: Capsule(style: .continuous))
        } else {
            content
                .background(Color.blue, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                )
        }
    }
}

private struct QRAuthPayload {
    let server: String
    let token: String?
    let user: String?
    let pass: String?
    let code: String?
}

private struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void
    var body: some View {
        ZStack {
            QRCodeScannerView { value in
                onCode(value)
                dismiss()
            }
            .ignoresSafeArea()
            ScannerOverlay().ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .padding(20)
                }
                Spacer()
            }
            VStack {
                Spacer()
                Text("Point your camera at the QR code")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 80)
            }
        }
    }
}

private struct ScannerOverlay: View {
    private let cutoutSize: CGFloat = 250
    private let cornerLength: CGFloat = 30
    private let cornerWidth: CGFloat = 4
    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(x: (geo.size.width - cutoutSize) / 2, y: (geo.size.height - cutoutSize) / 2 - 40, width: cutoutSize, height: cutoutSize)
            ZStack {
                Rectangle().fill(.black.opacity(0.55)).reverseMask {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).frame(width: cutoutSize, height: cutoutSize).position(x: rect.midX, y: rect.midY)
                }
                ViewfinderCorners(rect: rect, length: cornerLength, width: cornerWidth, radius: 20).stroke(.white, lineWidth: cornerWidth)
            }
        }
    }
}

private extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(ZStack { Rectangle(); mask().blendMode(.destinationOut) }.compositingGroup())
    }
}

private struct ViewfinderCorners: Shape {
    let rect: CGRect; let length: CGFloat; let width: CGFloat; let radius: CGFloat
    func path(in _: CGRect) -> Path {
        var p = Path(); let r = radius; let l = length
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r + l)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + r + l, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - r - l, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r + l))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r - l)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r - l, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + r + l, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r - l))
        return p
    }
}

private struct QRCodeScannerView: UIViewControllerRepresentable {
    let onFound: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController(); vc.onFound = onFound; return vc
    }
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?; private let session = AVCaptureSession(); private var previewLayer: AVCaptureVideoPreviewLayer?; private var didEmit = false
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .black; checkCameraPermissions() }
    private func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: setupSession()
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in if granted { DispatchQueue.main.async { self?.setupSession() } } }
        default: break
        }
    }
    private func setupSession() {
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) { session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr] }
        previewLayer = AVCaptureVideoPreviewLayer(session: session); previewLayer?.videoGravity = .resizeAspectFill; previewLayer?.frame = view.bounds
        if let pl = previewLayer { view.layer.addSublayer(pl) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); previewLayer?.frame = view.bounds }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didEmit, let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let value = obj.stringValue else { return }
        didEmit = true; onFound?(value)
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); if session.isRunning { session.stopRunning() } }
}
