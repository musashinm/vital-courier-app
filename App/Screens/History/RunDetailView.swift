import SwiftUI
import VitalCourierCore

struct RunDetailView: View {
    let run: RunRecord
    var body: some View { Text(run.trigger) }
}
