//
//  ContentView.swift
//  EchoSnap
//
//  Created by Justin Chen on 12/27/24.
//

import SwiftUI
import AVFoundation
import UIKit
import PhotosUI

extension Color {
    static let appGradientStart = Color(hex: "4A90E2")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let videoOrientation: AVCaptureVideoOrientation
    var onPinchGesture: ((UIPinchGestureRecognizer) -> Void)?
    var onDoubleTap: (() -> Void)?
    var onTapToFocus: ((CGPoint, CGRect, Bool) -> Void)?
    
    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            videoPreviewLayer.frame = bounds
        }
    }
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .systemBackground
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspect
        view.videoPreviewLayer.connection?.videoOrientation = videoOrientation
        
        // Add pinch gesture recognizer
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        // Add double tap gesture recognizer
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapGesture)
        
        // Add tap gesture recognizer for focus
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.require(toFail: doubleTapGesture)
        view.addGestureRecognizer(tapGesture)
        
        // Add long press gesture recognizer for focus lock
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPressGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.connection?.videoOrientation = videoOrientation
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: CameraPreview
        
        init(_ parent: CameraPreview) {
            self.parent = parent
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            parent.onPinchGesture?(gesture)
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            parent.onDoubleTap?()
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            parent.onTapToFocus?(point, gesture.view?.bounds ?? .zero, false)
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            let point = gesture.location(in: gesture.view)
            parent.onTapToFocus?(point, gesture.view?.bounds ?? .zero, true)
        }
    }
}

class CameraModel: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var recentImage: UIImage?
    @Published var isPhotoTaken = false
    @Published var isPreviewActive = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var focusPoint: CGPoint?
    @Published var isFocusLocked = false
    @Published var exposureBias: Float = 0.0
    @Published var isAdjustingExposure = false
    
    private var isCameraAuthorized = false
    private let output = AVCapturePhotoOutput()
    private var currentDevice: AVCaptureDevice?
    
    // Device properties
    private let minZoomFactor: CGFloat = 1.0
    private var maxZoomFactor: CGFloat = 1.0
    private var minExposureBias: Float = -8.0
    private var maxExposureBias: Float = 8.0
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    
    private func restartCameraSession() {
        // Clear image data for memory management
        recentImage = nil
        isPhotoTaken = false
        
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }
    
    func togglePreview() {
        withAnimation(.spring()) {
            isPreviewActive.toggle()
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            if self.isPreviewActive {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            } else {
                if self.session.isRunning {
                    self.session.stopRunning()
                }
            }
        }
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        
        // Configure for maximum quality
        settings.photoQualityPrioritization = .quality
        
        // Enable high quality capture
        settings.isHighResolutionPhotoEnabled = true
        
        // Set video orientation for capture
        if let connection = output.connection(with: .video) {
            connection.videoOrientation = CameraUtilities.videoOrientation()
        }
        
        output.capturePhoto(with: settings, delegate: self)
    }
    
    func savePhotoAndReopen() {
        if let image = recentImage {
            UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
        }
        restartCameraSession()
    }
    
    func discardPhotoAndReopen() {
        restartCameraSession()
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isCameraAuthorized = true
            DispatchQueue.global(qos: .userInitiated).async {
                self.setup()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.isCameraAuthorized = true
                        DispatchQueue.global(qos: .userInitiated).async {
                            self?.setup()
                        }
                    }
                }
            }
        default:
            self.isCameraAuthorized = false
        }
    }
    
    func setup() {
        do {
            session.beginConfiguration()
            
            // Remove any existing inputs and outputs
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("Failed to get camera device")
                return
            }
            
            // Store current device and configure zoom
            currentDevice = device
            maxZoomFactor = min(device.maxAvailableVideoZoomFactor, AppConstants.Camera.maxZoomFactor)
            
            // Configure camera for high quality photo capture
            try device.lockForConfiguration()
            
            // Select highest resolution format that supports photo capture
            let formats = device.formats.filter { format in
                format.isHighestPhotoQualitySupported &&
                CMFormatDescriptionGetMediaType(format.formatDescription) == kCMMediaType_Video
            }
            
            if let bestFormat = formats.max(by: { first, second in
                let firstDimensions = CMVideoFormatDescriptionGetDimensions(first.formatDescription)
                let secondDimensions = CMVideoFormatDescriptionGetDimensions(second.formatDescription)
                return firstDimensions.width * firstDimensions.height < secondDimensions.width * secondDimensions.height
            }) {
                device.activeFormat = bestFormat
                let dimensions = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
                print("Selected camera format: \(dimensions.width)x\(dimensions.height)")
            }
            
            device.unlockForConfiguration()
            
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                
                // Configure photo output for maximum quality
                output.maxPhotoQualityPrioritization = .quality
                
                // Enable high resolution capture
                output.isHighResolutionCaptureEnabled = true
            }
            
            session.sessionPreset = .photo
            
            session.commitConfiguration()
            
            if !session.isRunning {
                session.startRunning()
            }
        } catch {
            print("Failed to setup camera: \(error.localizedDescription)")
        }
    }
    
    deinit {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    func setZoomFactor(_ factor: CGFloat, animated: Bool = true) {
        guard let device = currentDevice else { return }
        
        do {
            try device.lockForConfiguration()
            let clampedFactor = max(minZoomFactor, min(factor, maxZoomFactor))
            
            if animated {
                device.ramp(toVideoZoomFactor: Double(clampedFactor), withRate: AppConstants.Camera.zoomAnimationRate)
            } else {
                device.videoZoomFactor = Double(clampedFactor)
            }
            
            device.unlockForConfiguration()
            DispatchQueue.main.async {
                self.zoomFactor = clampedFactor
            }
        } catch {
            print("Error setting zoom factor: \(error.localizedDescription)")
        }
    }
    
    func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
        guard currentDevice != nil else { return }
        
        switch gesture.state {
        case .changed:
            let newScaleFactor = zoomFactor * gesture.scale
            setZoomFactor(newScaleFactor, animated: false)
            gesture.scale = 1.0 // Reset scale for next gesture update
            
        case .ended:
            let newScaleFactor = zoomFactor * gesture.scale
            setZoomFactor(newScaleFactor, animated: true)
            gesture.scale = 1.0
            
        default:
            break
        }
    }
    
    func handleDoubleTap() {
        // Toggle between 1x and 2x zoom
        let targetZoom = zoomFactor > 1.5 ? 1.0 : 2.0
        setZoomFactor(targetZoom, animated: true)
    }
    
    func setExposureBias(_ bias: Float) {
        guard let device = currentDevice,
              device.isExposurePointOfInterestSupported else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Clamp the bias value between min and max
            let clampedBias = max(minExposureBias, min(bias, maxExposureBias))
            device.setExposureTargetBias(clampedBias) { _ in
                DispatchQueue.main.async {
                    self.exposureBias = clampedBias
                }
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error setting exposure bias: \(error.localizedDescription)")
        }
    }
    
    func handleExposureAdjustment(_ translation: CGFloat) {
        // Convert vertical translation to exposure bias with higher sensitivity for low-latency response
        let biasChange = Float(-translation) / AppConstants.Camera.exposureSensitivity
        let newBias = exposureBias + biasChange
        setExposureBias(newBias)
    }
    
    func setFocus(at point: CGPoint, isLocked: Bool = false) {
        guard let device = currentDevice,
              device.isFocusPointOfInterestSupported,
              device.isFocusModeSupported(.autoFocus) else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Convert point to focus point of interest
            device.focusPointOfInterest = point
            device.focusMode = isLocked ? .locked : .autoFocus
            
            // Set exposure point and mode
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = isLocked ? .locked : .continuousAutoExposure
            }
            
            // Always reset exposure bias to optimal (0.0) when setting focus
            // This ensures optimal exposure regardless of previous adjustments
            device.setExposureTargetBias(0.0) { _ in
                DispatchQueue.main.async {
                    self.exposureBias = 0.0
                }
            }
            
            device.unlockForConfiguration()
            
            // Update UI state
            DispatchQueue.main.async {
                self.focusPoint = point
                self.isFocusLocked = isLocked
                
                // Clear focus point after animation if not locked
                if !isLocked {
                    DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Camera.focusClearDelay) {
                        if !self.isAdjustingExposure {
                            self.focusPoint = nil
                        }
                    }
                }
            }
        } catch {
            print("Error setting focus: \(error.localizedDescription)")
        }
    }
    
    func handleTapToFocus(_ point: CGPoint, in bounds: CGRect, longPress: Bool = false) {
        // Convert tap point to focus point of interest coordinates (0,0 to 1,1)
        let focusPoint = CGPoint(
            x: point.x / bounds.width,
            y: point.y / bounds.height
        )
        
        setFocus(at: focusPoint, isLocked: longPress)
    }
    
    func unlockFocus() {
        guard let device = currentDevice,
              device.isFocusPointOfInterestSupported else { return }
        
        do {
            try device.lockForConfiguration()
            device.focusMode = .continuousAutoFocus
            if device.isExposurePointOfInterestSupported {
                device.exposureMode = .continuousAutoExposure
            }
            
            // Reset exposure bias to optimal when unlocking focus
            device.setExposureTargetBias(0.0) { _ in
                DispatchQueue.main.async {
                    self.exposureBias = 0.0
                }
            }
            
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                self.isFocusLocked = false
                self.focusPoint = nil
            }
        } catch {
            print("Error unlocking focus: \(error.localizedDescription)")
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let imageData = photo.fileDataRepresentation(),
           let image = UIImage(data: imageData) {
            DispatchQueue.main.async {
                withAnimation(.spring()) {
                    self.recentImage = image
                    self.isPhotoTaken = true
                }
                
                DispatchQueue.global(qos: .userInitiated).async {
                    self.session.stopRunning()
                }
            }
        }
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            print("Error saving photo: \(error.localizedDescription)")
        } else {
            print("Photo saved successfully")
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    @Binding var selectedImage: UIImage?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// Photo Library Permission Handler
struct PhotoLibraryPermissionHandler: ViewModifier {
    @Binding var showImagePicker: Bool
    
    func body(content: Content) -> some View {
        content
            .onChange(of: showImagePicker) { _, newValue in
                if newValue {
                    PHPhotoLibrary.requestAuthorization { status in
                        DispatchQueue.main.async {
                            if status != .authorized {
                                showImagePicker = false
                            }
                        }
                    }
                }
            }
    }
}

extension View {
    func handlePhotoLibraryPermission(showImagePicker: Binding<Bool>) -> some View {
        self.modifier(PhotoLibraryPermissionHandler(showImagePicker: showImagePicker))
    }
}

// Add these utility functions before ContentView
private struct ViewUtilities {
    static func calculateImageSize(geometry: GeometryProxy, image: UIImage, isLandscape: Bool) -> CGSize {
        let containerWidth = geometry.size.width
        let containerHeight = geometry.size.height
        let imageAspectRatio = image.size.width / image.size.height
        
        if isLandscape {
            let maxHeight = containerHeight * 0.9 // 90% of container height
            let width = maxHeight * imageAspectRatio
            if width <= containerWidth {
                return CGSize(width: width, height: maxHeight)
            } else {
                let maxWidth = containerWidth * 0.9 // 90% of container width
                return CGSize(width: maxWidth, height: maxWidth / imageAspectRatio)
            }
        } else {
            let maxWidth = containerWidth * 0.9 // 90% of container width
            let height = maxWidth / imageAspectRatio
            if height <= containerHeight {
                return CGSize(width: maxWidth, height: height)
            } else {
                let maxHeight = containerHeight * 0.9 // 90% of container height
                return CGSize(width: maxHeight * imageAspectRatio, height: maxHeight)
            }
        }
    }
    
    static func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appGradientStart.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 4)
    }
}

struct ZoomableImageView: View {
    let image: UIImage
    @Binding var shouldReset: Bool
    @Binding var isTransformed: Bool
    let isLandscape: Bool
    let cornerRadius: CGFloat
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var rotation: Angle = .zero
    @State private var lastRotation: Angle = .zero
    
    private func checkTransformation() {
        isTransformed = scale != 1.0 || offset != .zero || rotation != .zero
    }
    
    private func resetTransformation() {
        withAnimation(.spring()) {
            scale = 1.0
            offset = .zero
            rotation = .zero
        }
        checkTransformation()
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale = scale * delta
                checkTransformation()
            }
            .onEnded { _ in
                lastScale = 1.0
            }
    }
    
    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { value in
                let delta = value - lastRotation
                lastRotation = value
                rotation += delta
                checkTransformation()
            }
            .onEnded { _ in
                lastRotation = .zero
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastOffset.width,
                    height: value.translation.height - lastOffset.height
                )
                lastOffset = value.translation
                offset = CGSize(
                    width: offset.width + delta.width,
                    height: offset.height + delta.height
                )
                checkTransformation()
            }
            .onEnded { _ in
                lastOffset = .zero
            }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = ViewUtilities.calculateImageSize(geometry: geometry, image: image, isLandscape: isLandscape)
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .scaleEffect(scale)
                .offset(offset)
                .rotationEffect(rotation)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .gesture(
                    SimultaneousGesture(
                        SimultaneousGesture(magnificationGesture, rotationGesture),
                        dragGesture
                    )
                )
                .highPriorityGesture(
                    TapGesture(count: 2)
                        .onEnded { resetTransformation() }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in }
                )
                .onChange(of: shouldReset) { _, newValue in
                    if newValue {
                        resetTransformation()
                        shouldReset = false
                    }
                }
        }
    }
}

struct DeviceRotationViewModifier: ViewModifier {
    let action: (UIDeviceOrientation) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear()
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                action(UIDevice.current.orientation)
            }
    }
}

extension View {
    func onRotate(perform action: @escaping (UIDeviceOrientation) -> Void) -> some View {
        self.modifier(DeviceRotationViewModifier(action: action))
    }
}

// Exposure Control View
struct ExposureControl: View {
    let exposureBias: Float
    let isAdjusting: Bool
    @State private var isOptimalHighlight = false
    
    var body: some View {
        ZStack {
            // Vertical line background
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 2, height: 40)
            
            // Sun icon that slides on the line - centered by default
            Image(systemName: "sun.max.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(sunIconColor)
                .offset(y: calculateSunOffset())
                .animation(AppConstants.Animations.exposureLinear, value: exposureBias)
                .onChange(of: exposureBias) { _, newValue in
                    // Briefly highlight when exposure is reset to optimal
                    if newValue == 0.0 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isOptimalHighlight = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isOptimalHighlight = false
                            }
                        }
                    }
                }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
    
    private var sunIconColor: Color {
        if isOptimalHighlight {
            return .yellow
        } else {
            return .white
        }
    }
    
    // Calculate sun position based on exposure bias
    private func calculateSunOffset() -> CGFloat {
        // Map exposure bias (-8 to 8) to vertical position (-20 to 20)
        // Center the sun at 0 (exposureBias = 0), with positive bias moving up (brighter) and negative bias moving down (darker)
        let normalizedBias = CGFloat(exposureBias) / 8.0
        // Center the sun by starting at 0 and moving up/down from there
        return -normalizedBias * 20
    }
}

// Focus Square View
struct FocusSquare: View {
    let point: CGPoint
    let isLocked: Bool
    let exposureBias: Float
    let isAdjustingExposure: Bool
    @State private var isAnimating = false
    
    var body: some View {
        let size: CGFloat = 85
        let innerSize: CGFloat = isAnimating ? 70 : 85
        
        ZStack {
            // Outer square
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: size, height: size)
            
            // Inner square
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: innerSize, height: innerSize)
            
            // Lock indicator
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .offset(y: -(size/2 + 20))
            }
            
            // Exposure control
            ExposureControl(exposureBias: exposureBias, isAdjusting: isAdjustingExposure)
                .offset(x: size/2 + 20)
        }
        .position(x: point.x, y: point.y)
        .onAppear {
            withAnimation(AppConstants.Animations.focusAnimation) {
                isAnimating = true
            }
        }
    }
}

// Camera Preview Container
struct CameraPreviewContainer: View {
    let geometry: GeometryProxy
    let isLandscape: Bool
    let session: AVCaptureSession
    let videoOrientation: AVCaptureVideoOrientation
    let controls: () -> AnyView
    @ObservedObject var camera: CameraModel
    @GestureState private var dragState: CGFloat = 0
    
    var body: some View {
        let containerScale: CGFloat = 0.9  // Extract the common scale factor
        let maxWidth = geometry.size.width * containerScale
        let maxHeight = geometry.size.height * containerScale
        
        ZStack {
            // Camera preview
            CameraPreview(
                session: session,
                videoOrientation: videoOrientation,
                onPinchGesture: { gesture in
                    camera.handlePinchGesture(gesture)
                },
                onDoubleTap: {
                    camera.handleDoubleTap()
                },
                onTapToFocus: { point, bounds, isLocked in
                    camera.handleTapToFocus(point, in: bounds, longPress: isLocked)
                }
            )
            .frame(width: maxWidth, height: maxHeight)
            // Add drag gesture to the entire preview when focus point exists
            .gesture(
                camera.focusPoint == nil ? nil :
                    DragGesture()
                        .updating($dragState) { value, state, _ in
                            state = value.translation.height
                            camera.isAdjustingExposure = true
                            // Use accumulated translation for more responsive adjustment
                            camera.handleExposureAdjustment(value.translation.height)
                        }
                        .onEnded { _ in
                            camera.isAdjustingExposure = false
                            if !camera.isFocusLocked {
                                DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.Camera.exposureClearDelay) {
                                    camera.focusPoint = nil
                                }
                            }
                        }
            )
            
            // Focus square with exposure control
            if let focusPoint = camera.focusPoint {
                FocusSquare(
                    point: CGPoint(
                        x: focusPoint.x * maxWidth,
                        y: focusPoint.y * maxHeight
                    ),
                    isLocked: camera.isFocusLocked,
                    exposureBias: camera.exposureBias,
                    isAdjustingExposure: camera.isAdjustingExposure
                )
            }
            
            // Zoom indicator (only show when zooming) - positioned at bottom right corner within bounds
            if camera.zoomFactor > 1.01 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(String(format: "%.1fx", camera.zoomFactor))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
            
            // Controls overlay positioned relative to the full container
            AnyView(controls())
        }
    }
}

// Captured Photo View
struct CapturedPhotoView: View {
    let image: UIImage
    let cornerRadius: CGFloat
    let photoActions: () -> AnyView
    
    var body: some View {
        GeometryReader { geometry in
            let size = ViewUtilities.calculateImageSize(geometry: geometry, image: image, isLandscape: false)
            
            ZStack {
                // Photo preview with consistent size
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .background(ViewUtilities.cardBackground(cornerRadius: cornerRadius))
                
                // Bottom-right buttons
                VStack {
                    HStack {
                        Spacer()
                        AnyView(photoActions())
                    }
                    Spacer()
                }
            }
            .position(x: geometry.size.width/2, y: geometry.size.height/2)
        }
    }
}

// Info View
struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var camera: CameraModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Image("logo-info-page")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                    
                    VStack(spacing: 16) {
                        Text("EchoSnap")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.appGradientStart)
                        
                        Text("© 2025 nerdyStuff")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 12) {
                        Link(destination: URL(string: "https://www.nerdystuff.xyz")!) {
                            HStack {
                                Text("About Us")
                                Spacer()
                                Image(systemName: "arrow.up.right.circle.fill")
                            }
                            .foregroundColor(.appGradientStart)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.appGradientStart.opacity(0.1))
                            )
                        }
                        
                        Link(destination: URL(string: "https://www.nerdystuff.xyz/pages/contact-us")!) {
                            HStack {
                                Text("Contact")
                                Spacer()
                                Image(systemName: "arrow.up.right.circle.fill")
                            }
                            .foregroundColor(.appGradientStart)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.appGradientStart.opacity(0.1))
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 0)
                }
                .padding(.top, 40)
                .frame(maxWidth: 400) // Fixed maximum width
                .frame(maxHeight: .infinity)
                .padding(.horizontal)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Forces modal style in all orientations
    }
}

// Glowing Icon Button
struct GlowingIconButton: View {
    let systemName: String
    let action: () -> Void
    
    // Convert system name to asset name
    private var imageName: String {
        switch systemName {
        case "xmark.circle.fill":
            return "button-close"
        case "checkmark.circle.fill":
            return "button-accept"
        case "arrow.counterclockwise.circle":
            return "button-reset"
        default:
            return ""
        }
    }
    
    var body: some View {
        Button(action: action) {
            Image(imageName)
                .resizable()
                .frame(width: 44, height: 44)
        }
    }
}

struct ContentView: View {
    @State private var showImagePicker = false
    @State private var referenceImage: UIImage?
    @State private var shouldResetImage = false
    @State private var isImageTransformed = false
    @StateObject private var camera = CameraModel()
    @State private var orientation = UIDevice.current.orientation
    @State private var showInfoView = false
    
    
    private var isLandscape: Bool {
        // Get the interface orientation instead of device orientation
        let interfaceOrientation = UIWindow.key?.windowScene?.interfaceOrientation ?? .portrait
        return interfaceOrientation.isLandscape
    }
    
    private var videoOrientation: AVCaptureVideoOrientation {
        return CameraUtilities.videoOrientation()
    }
    
    private func handleOrientationChange(_ newOrientation: UIDeviceOrientation) {
        // Only handle actual orientation changes that match interface orientations
        if orientation != newOrientation {
            switch newOrientation {
            case .portrait, .landscapeLeft, .landscapeRight:
                orientation = newOrientation
                
                // Only handle camera preview if it's active and no photo is taken
                if camera.isPreviewActive && !camera.isPhotoTaken {
                    camera.isPreviewActive = false
                    
                    DispatchQueue.global(qos: .userInitiated).async {
                        camera.session.stopRunning()
                        
                        // Reopen camera preview after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            camera.togglePreview()
                        }
                    }
                }
            default:
                // Ignore other orientations (face up, face down, portrait upside down)
                break
            }
        }
    }
    
    // Helper view for the photo action buttons
    private func photoActionButtons() -> some View {
        VStack(spacing: AppConstants.UI.buttonSpacing) {
            GlowingIconButton(systemName: "checkmark.circle.fill") {
                withAnimation(.spring()) {
                    camera.savePhotoAndReopen()
                }
            }
            
            GlowingIconButton(systemName: "xmark.circle.fill") {
                withAnimation(.spring()) {
                    camera.discardPhotoAndReopen()
                }
            }
        }
        .padding(AppConstants.UI.standardPadding)
    }
    
    // Helper view for the reference image buttons
    private func referenceImageButtons() -> some View {
        VStack(spacing: AppConstants.UI.buttonSpacing) {
            GlowingIconButton(systemName: "xmark.circle.fill") {
                withAnimation(.spring()) {
                    self.referenceImage = nil
                }
            }
            
            if isImageTransformed {
                GlowingIconButton(systemName: "arrow.counterclockwise.circle") {
                    shouldResetImage = true
                }
            }
        }
        .padding(AppConstants.UI.standardPadding)
    }
    
    // Helper view for the camera preview controls
    private func cameraPreviewControls() -> some View {
        ZStack {
            // Camera preview with capture button
            VStack {
                Spacer()
                Button(action: {
                    camera.capturePhoto()
                }) {
                    Circle()
                        .fill(Color.appGradientStart)
                        .frame(width: AppConstants.UI.captureButtonSize, height: AppConstants.UI.captureButtonSize)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.1)
                                .padding(4)
                        )
                }
                .padding(.bottom, captureButtonBottomPadding)
            }
            
            // Top-right close button
            VStack {
                HStack {
                    Spacer()
                    GlowingIconButton(systemName: "xmark.circle.fill") {
                        withAnimation(.spring()) {
                            camera.togglePreview()
                        }
                    }
                    .padding(AppConstants.UI.standardPadding)
                }
                Spacer()
            }
        }
    }
    
    // Calculate appropriate bottom padding for capture button to maintain consistent distance from camera preview border
    private var captureButtonBottomPadding: CGFloat {
        let baseSpacing = AppConstants.UI.standardPadding + 8 // 24 points from camera preview border
        
        if isLandscape {
            // In landscape, camera preview is scaled down to 90%, so we need extra padding
            // to account for the 5% margin at the bottom (since containerScale = 0.9)
            let containerMargin = (1.0 - AppConstants.UI.containerScale) / 2.0 // 0.05 (5%)
            let extraPaddingNeeded = containerMargin * UIScreen.main.bounds.height
            return baseSpacing + extraPaddingNeeded
        } else {
            // Portrait mode: standard spacing from camera preview border
            return baseSpacing
        }
    }
    
    // Add title banner view
    private func titleBanner() -> some View {
        ZStack {
            Text("EchoSnap")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.appGradientStart)
            
            HStack {
                Spacer()
                Button(action: { showInfoView = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: AppConstants.UI.buttonSize))
                        .foregroundColor(.appGradientStart)
                }
                .frame(width: 44)  // Fixed width for the button area
            }
        }
        .frame(height: AppConstants.UI.bannerHeight)
        .padding(.horizontal, AppConstants.UI.cardPadding)
    }
    
    // Enhanced Placeholder View
    struct EnhancedPlaceholder: View {
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.appGradientStart)
                    
                    Text("Tap to Select Reference Image")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.appGradientStart)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appGradientStart.opacity(0.3), lineWidth: 2)
                        )
                )
                .padding(20)
            }
        }
    }
    
    // Enhanced Camera Placeholder View  
    struct EnhancedCameraPlaceholder: View {
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 16) {
                    Image(systemName: "camera.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.appGradientStart)
                    
                    Text("Tap to Open Camera")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.appGradientStart)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appGradientStart.opacity(0.3), lineWidth: 2)
                        )
                )
                .padding(20)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            titleBanner()
            
            GeometryReader { geometry in
                if isLandscape {
                    // Landscape layout
                    HStack(spacing: AppConstants.UI.cardSpacing) {
                        // Left half: Reference Image
                        ZStack {
                            ViewUtilities.cardBackground(cornerRadius: AppConstants.UI.cardCornerRadius)
                            
                            if let referenceImage = referenceImage {
                                ZStack {
                                    ZoomableImageView(
                                        image: referenceImage,
                                        shouldReset: $shouldResetImage,
                                        isTransformed: $isImageTransformed,
                                        isLandscape: true,
                                        cornerRadius: AppConstants.UI.cardCornerRadius
                                    )
                                    
                                    // Top-right buttons
                                    VStack {
                                        HStack {
                                            Spacer()
                                            referenceImageButtons()
                                        }
                                        Spacer()
                                    }
                                }
                            } else {
                                EnhancedPlaceholder(action: { showImagePicker = true })
                            }
                        }
                        .frame(width: (geometry.size.width - AppConstants.UI.cardSpacing - AppConstants.UI.cardPadding * 2 - 32) / 2)
                        .scaleEffect(AppConstants.UI.scaleEffect)
                        
                        // Right half: Camera
                        ZStack {
                            ViewUtilities.cardBackground(cornerRadius: AppConstants.UI.cardCornerRadius)
                            
                            if !camera.isPreviewActive {
                                EnhancedCameraPlaceholder(action: { camera.togglePreview() })
                            } else if let capturedImage = camera.recentImage, camera.isPhotoTaken {
                                CapturedPhotoView(
                                    image: capturedImage,
                                    cornerRadius: AppConstants.UI.cardCornerRadius,
                                    photoActions: { AnyView(photoActionButtons()) }
                                )
                            } else {
                                GeometryReader { geo in
                                    CameraPreviewContainer(
                                        geometry: geo,
                                        isLandscape: isLandscape,
                                        session: camera.session,
                                        videoOrientation: videoOrientation,
                                        controls: { AnyView(cameraPreviewControls()) },
                                        camera: camera
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                        .frame(width: (geometry.size.width - AppConstants.UI.cardSpacing - AppConstants.UI.cardPadding * 2 - 32) / 2)
                        .scaleEffect(0.95)  // Scale to 95%
                    }
                    .padding(.horizontal, AppConstants.UI.cardPadding)
                    .padding(.top, AppConstants.UI.cardPadding)
                    .padding(.bottom, 16)  // Add bottom padding
                    .padding(.leading, 16) // Notch protection
                    .padding(.trailing, 16) // Right margin
                } else {
                    // Portrait layout
                    VStack(spacing: AppConstants.UI.cardSpacing) {
                        // Top half: Reference Image
                        ZStack {
                            ViewUtilities.cardBackground(cornerRadius: AppConstants.UI.cardCornerRadius)
                            
                            if let referenceImage = referenceImage {
                                ZStack {
                                    ZoomableImageView(
                                        image: referenceImage,
                                        shouldReset: $shouldResetImage,
                                        isTransformed: $isImageTransformed,
                                        isLandscape: false,
                                        cornerRadius: AppConstants.UI.cardCornerRadius
                                    )
                                    
                                    // Top-right buttons
                                    VStack {
                                        HStack {
                                            Spacer()
                                            referenceImageButtons()
                                        }
                                        Spacer()
                                    }
                                }
                            } else {
                                EnhancedPlaceholder(action: { showImagePicker = true })
                            }
                        }
                        .frame(height: (geometry.size.height - AppConstants.UI.cardSpacing - AppConstants.UI.cardPadding * 2 - 16) / 2)
                        
                        // Bottom half: Camera
                        ZStack {
                            ViewUtilities.cardBackground(cornerRadius: AppConstants.UI.cardCornerRadius)
                            
                            if !camera.isPreviewActive {
                                EnhancedCameraPlaceholder(action: { camera.togglePreview() })
                            } else if let capturedImage = camera.recentImage, camera.isPhotoTaken {
                                CapturedPhotoView(
                                    image: capturedImage,
                                    cornerRadius: AppConstants.UI.cardCornerRadius,
                                    photoActions: { AnyView(photoActionButtons()) }
                                )
                            } else {
                                GeometryReader { geo in
                                    CameraPreviewContainer(
                                        geometry: geo,
                                        isLandscape: isLandscape,
                                        session: camera.session,
                                        videoOrientation: videoOrientation,
                                        controls: { AnyView(cameraPreviewControls()) },
                                        camera: camera
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                        .frame(height: (geometry.size.height - AppConstants.UI.cardSpacing - AppConstants.UI.cardPadding * 2 - 16) / 2)
                    }
                    .padding(.horizontal, AppConstants.UI.cardPadding)
                    .padding(.top, AppConstants.UI.cardPadding)
                    .padding(.bottom, 16)
                }
            }
        }
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $referenceImage)
        }
        .handlePhotoLibraryPermission(showImagePicker: $showImagePicker)
        .sheet(isPresented: $showInfoView) {
            InfoView(camera: camera)
        }
        .onRotate { newOrientation in
            handleOrientationChange(newOrientation)
        }
    }
}

#Preview {
    ContentView()
}

extension UIWindow {
    static var key: UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return scene.windows.first(where: { $0.isKeyWindow })
    }
}

// MARK: - Constants & Utilities
private enum AppConstants {
    enum UI {
        static let buttonSize: CGFloat = 24
        static let captureButtonSize: CGFloat = 54
        static let buttonSpacing: CGFloat = 2
        static let standardPadding: CGFloat = 16
        static let bannerHeight: CGFloat = 30
        static let cardPadding: CGFloat = 12
        static let cardSpacing: CGFloat = 4
        static let cardCornerRadius: CGFloat = 12
        static let containerScale: CGFloat = 0.9
        static let imageScale: CGFloat = 0.9
        static let scaleEffect: CGFloat = 0.95
    }
    
    enum Camera {
        static let maxZoomFactor: CGFloat = 5.0
        static let minExposureBias: Float = -8.0
        static let maxExposureBias: Float = 8.0
        static let zoomAnimationRate: Float = 4.0
        static let exposureSensitivity: Float = 50.0
        static let orientationDelay: TimeInterval = 0.5
        static let focusClearDelay: TimeInterval = 1.0
        static let exposureClearDelay: TimeInterval = 0.5
    }
    
    enum Animations {
        static var spring: SwiftUI.Animation { SwiftUI.Animation.spring() }
        static var exposureLinear: SwiftUI.Animation { SwiftUI.Animation.linear(duration: 0.05) }
        static var focusAnimation: SwiftUI.Animation { SwiftUI.Animation.easeInOut(duration: 0.3).repeatCount(1, autoreverses: true) }
    }
}

private enum CameraUtilities {
    static func videoOrientation() -> AVCaptureVideoOrientation {
        let interfaceOrientation = UIWindow.key?.windowScene?.interfaceOrientation ?? .portrait
        
        switch interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .portrait
        }
    }
}
