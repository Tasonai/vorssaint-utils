// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Darwin
import Foundation

struct MixerOutputDevice: Identifiable, Equatable {
    let id: String
    let uid: String
    let name: String
    let isDefault: Bool
    let isHeadphones: Bool
    let canBeDefaultOutput: Bool
    let canBeDefaultSystemOutput: Bool
    let priorityTier: MixerRoutingSupport.PriorityTier
    let audioObjectID: AudioObjectID

    init(id: String, uid: String, name: String, isDefault: Bool, isHeadphones: Bool,
         canBeDefaultOutput: Bool, canBeDefaultSystemOutput: Bool,
         priorityTier: MixerRoutingSupport.PriorityTier, audioObjectID: AudioObjectID) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isDefault = isDefault
        self.isHeadphones = isHeadphones
        self.canBeDefaultOutput = canBeDefaultOutput
        self.canBeDefaultSystemOutput = canBeDefaultSystemOutput
        self.priorityTier = priorityTier
        self.audioObjectID = audioObjectID
    }
}

/// One app in the mixer: every audio-producing process it is responsible for,
/// rolled into a single row.
struct MixerApp: Identifiable, Equatable {
    /// Identifies the row and its engine while the app runs.
    let id: String
    /// The key this row's volume and route are saved under: bundle id, or
    /// display name for a process without one. Nil when neither exists; such
    /// a row is still listed and adjustable, but writes nothing to disk.
    let persistenceID: String?
    let ownerPid: pid_t
    let name: String
    let audioObjects: [AudioObjectID]
    /// True while the app is actually emitting sound right now (shown as a
    /// live indicator). Apps appear in the mixer even when momentarily silent,
    /// as long as they hold an audio connection.
    let isPlaying: Bool
    /// The app's audio is left untouched: no slider or routing, unity volume.
    /// Keep its row visible so its absence doesn't read as a bug (issue #177).
    var isBypassed: Bool = false
    /// Discord and Teams can opt back into volume control when not sharing audio.
    var supportsVolumeOverride: Bool = false
    /// A manual universal switch found this process still playing elsewhere.
    /// Keep its route at unity too, without saving a per-app device preference.
    var universalOutputRouteUID: String? = nil
    var selectedOutputDeviceUID: String?
    var effectiveOutputDeviceUID: String?
    var outputDeviceUnavailable: Bool
    var volume: Double

    var identity: MixerRowIdentity {
        MixerRowIdentity(rowID: id, persistenceID: persistenceID)
    }
}

/// An app the user took out of the mixer list, remembered by name so it can
/// be brought back even while it is not running (issue #300).
struct MixerHiddenApp: Identifiable, Equatable {
    let id: String
    let name: String
}
