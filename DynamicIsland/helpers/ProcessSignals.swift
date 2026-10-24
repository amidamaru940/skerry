/*
 * Skerry — a fork of Atoll (DynamicIsland)
 * Copyright (C) 2026 amidamaru940 and Skerry contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Darwin
import Foundation

/// Signals to the user's own processes by name, without starting `killall`:
/// the process list and kill(2) answer at once, so this may run on the main
/// thread at launch.
enum ProcessSignals {
    /// The pids whose name (`proc_name`, at most 32 characters) is in `names`.
    static func pids(named names: Set<String>) -> [pid_t] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }
        var name = [CChar](repeating: 0, count: 64)
        return pids.prefix(Int(count)).filter { pid in
            guard pid > 0, proc_name(pid, &name, UInt32(name.count)) > 0 else { return false }
            return names.contains(String(cString: name))
        }
    }

    /// Resumes every process of these names. Harmless for one that is not
    /// stopped. Returns how many were signalled.
    @discardableResult
    static func continueProcesses(named names: Set<String>) -> Int {
        pids(named: names).reduce(0) { sent, pid in sent + (kill(pid, SIGCONT) == 0 ? 1 : 0) }
    }
}
