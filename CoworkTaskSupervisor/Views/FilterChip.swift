import SwiftUI

struct FilterChip: View {
  let label: String;
  let isSelected: Bool;
  let action: () -> Void;

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}
