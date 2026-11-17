//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import VideoToolbox

/// Utility for deciding whether to offer H.265
///
/// H.265 is only ever offered when the device can encode/decode it in
/// hardware. It's never encoded or decoded in software, not even when using
/// the debug overrides.
public enum RingrtcH265Config {
    public static func enableH265Encode(with remoteConfig: RemoteConfig) -> Bool {
        guard hasHardwareEncoder else {
            return false
        }

        if DebugFlags.callingOverrideCodecs.get() {
            return DebugFlags.callingEnableH265Encode.get()
        }

        guard let hwIdentifier = String(sysctlKey: "hw.machine") else {
            return false
        }

        return remoteConfig.ringrtcH265Enabled &&
            !remoteConfig.ringrtcH265DeviceModelEncodeDenylist.contains(hwIdentifier)
    }

    public static func enableH265Decode(with remoteConfig: RemoteConfig) -> Bool {
        guard hasHardwareDecoder else {
            return false
        }

        if DebugFlags.callingOverrideCodecs.get() {
            return DebugFlags.callingEnableH265Decode.get()
        }

        guard let hwIdentifier = String(sysctlKey: "hw.machine") else {
            return false
        }

        return remoteConfig.ringrtcH265Enabled &&
            !remoteConfig.ringrtcH265DeviceModelDecodeDenylist.contains(hwIdentifier)
    }

    // MARK: - Hardware support

    /// The largest resolution used for 1:1 calls.
    private static let probeWidth: Int32 = 1280
    private static let probeHeight: Int32 = 720

    /// Whether VideoToolbox can decode H.265 in hardware on this device.
    private static let hasHardwareDecoder: Bool = {
#if targetEnvironment(simulator)
        return false
#else
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
#endif
    }()

    /// Whether VideoToolbox can encode H.265 in hardware on this device.
    ///
    /// There's no direct query for this, so check by creating (and discarding)
    /// a compression session.
    private static let hasHardwareEncoder: Bool = {
#if targetEnvironment(simulator)
        return false
#else
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: probeWidth,
            height: probeHeight,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session,
        )
        guard status == noErr, let session else {
            return false
        }
        defer { VTCompressionSessionInvalidate(session) }

        guard #available(iOS 17.4, *) else {
            // iOS devices only have hardware H.265 encoders, and older
            // versions can't report how a session encodes.
            return true
        }
        var usingHardware: CFBoolean?
        let propertyStatus = withUnsafeMutablePointer(to: &usingHardware) {
            VTSessionCopyProperty(
                session,
                key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
                allocator: nil,
                valueOut: $0,
            )
        }
        guard propertyStatus == noErr, let usingHardware else {
            // iOS devices only have hardware H.265 encoders, so a session
            // that doesn't report how it encodes is still a hardware one.
            return true
        }
        return CFBooleanGetValue(usingHardware)
#endif
    }()
}
