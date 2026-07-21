import SwiftUI

struct DetailSection<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .padding(.leading, 3)

      VStack(spacing: 0) {
        content
      }
      .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.primary.opacity(0.055), lineWidth: 1)
      }
    }
  }
}

struct DetailRow: View {
  let title: String
  let value: String
  var monospaced = false

  var body: some View {
    HStack(spacing: 14) {
      Text(title)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value)
        .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
  }
}

struct DetailDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 14)
  }
}

struct PieceMapView: View {
  let task: Aria2Task

  private let cellSize: CGFloat = 9
  private let spacing: CGFloat = 3
  private let maximumSamples = 480

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      if samples.isEmpty {
        Text(L10n.tr("task_detail.pieces_unavailable"))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      } else {
        Canvas { context, _ in
          for (index, ratio) in samples.enumerated() {
            let column = index % columnCount
            let row = index / columnCount
            let origin = CGPoint(
              x: CGFloat(column) * (cellSize + spacing),
              y: CGFloat(row) * (cellSize + spacing)
            )
            let rect = CGRect(origin: origin, size: CGSize(width: cellSize, height: cellSize))
            context.fill(
              Path(roundedRect: rect, cornerRadius: 2),
              with: .color(color(for: ratio))
            )
          }
        }
        .frame(width: mapWidth, height: mapHeight)
        .accessibilityLabel(L10n.tr("task_detail.piece_distribution.accessibility"))
        .accessibilityValue(L10n.format(
          "task_detail.pieces_completed_accessibility",
          String(completedPieceCount),
          String(task.numPieces)
        ))

        HStack(spacing: 16) {
          PieceLegend(color: .teal, title: L10n.tr("task.status.completed"))
          PieceLegend(color: Color.primary.opacity(0.1), title: L10n.tr("task_detail.piece_incomplete"))
          if task.numPieces > maximumSamples {
            PieceLegend(color: .teal.opacity(0.46), title: L10n.tr("task_detail.piece_mixed"))
          }
          Spacer()
          Text("\(completedPieceCount) / \(task.numPieces)")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  private var completedPieceCount: Int {
    task.pieceCompletion.filter { $0 }.count
  }

  private var samples: [Double] {
    let pieces = task.pieceCompletion
    guard pieces.count == task.numPieces, !pieces.isEmpty else { return [] }

    let sampleCount = min(maximumSamples, pieces.count)
    return (0..<sampleCount).map { index in
      let start = index * pieces.count / sampleCount
      let end = max(start + 1, (index + 1) * pieces.count / sampleCount)
      let completed = pieces[start..<end].reduce(0) { $0 + ($1 ? 1 : 0) }
      return Double(completed) / Double(end - start)
    }
  }

  private var columnCount: Int {
    guard !samples.isEmpty else { return 1 }
    let preferred = Int(ceil(sqrt(Double(samples.count) * 4)))
    return min(samples.count, min(48, max(16, preferred)))
  }

  private var rowCount: Int {
    guard !samples.isEmpty else { return 1 }
    return Int(ceil(Double(samples.count) / Double(columnCount)))
  }

  private var mapWidth: CGFloat {
    CGFloat(columnCount) * cellSize + CGFloat(max(0, columnCount - 1)) * spacing
  }

  private var mapHeight: CGFloat {
    CGFloat(rowCount) * cellSize + CGFloat(max(0, rowCount - 1)) * spacing
  }

  private func color(for ratio: Double) -> Color {
    if ratio >= 1 { return .teal }
    if ratio <= 0 { return Color.primary.opacity(0.1) }
    return .teal.opacity(0.3 + ratio * 0.5)
  }
}

private struct PieceLegend: View {
  let color: Color
  let title: String

  var body: some View {
    HStack(spacing: 5) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(color)
        .frame(width: 8, height: 8)
      Text(title)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
  }
}

struct DetailEmptyRow: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
  }
}

struct DetailTextRow: View {
  let image: String
  let text: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: image)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(width: 18)
      Text(text)
        .font(.system(size: 12, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }
}

struct PeerRow: View {
  let peer: Aria2Peer

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: peer.isSeeder ? "arrow.up.circle.fill" : "person.crop.circle")
        .font(.system(size: 15))
        .foregroundStyle(peer.isSeeder ? .indigo : .secondary)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 3) {
        Text(peer.address)
          .font(.system(size: 12, weight: .medium, design: .monospaced))
          .lineLimit(1)
        Text(peer.isSeeder ? L10n.tr("task_detail.seeder") : peer.isChoking ? L10n.tr("task_detail.piece_sampled") : L10n.tr("task_detail.transferring"))
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 14)

      VStack(alignment: .trailing, spacing: 3) {
        Label(Formatting.speed(peer.downloadSpeed), systemImage: "arrow.down")
        Label(Formatting.speed(peer.uploadSpeed), systemImage: "arrow.up")
      }
      .font(.system(size: 10, design: .rounded))
      .foregroundStyle(.secondary)
      .monospacedDigit()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
  }
}

struct TaskFileRow: View {
  let file: Aria2TaskFile

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: file.isSelected ? "doc.fill" : "doc")
        .font(.system(size: 15))
        .foregroundStyle(file.isSelected ? .teal : .secondary)
        .frame(width: 22)

      VStack(alignment: .leading, spacing: 5) {
        Text(file.name)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
        ProgressView(value: file.progress)
          .tint(.teal)
      }

      Spacer(minLength: 18)

      Text("\(Formatting.bytes(file.completedLength)) / \(Formatting.bytes(file.length))")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }
}
