import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
  static let torrent = UTType(filenameExtension: "torrent") ?? .data
}

struct MainWindowView: View {
  @ObservedObject var model: MainWindowModel

  var body: some View {
    HStack(spacing: 0) {
      sidebar
        .frame(width: 184)

      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .sheet(isPresented: $model.showingAddTask) {
      AddTaskSheet(model: model)
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Motrix Native")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.primary)
        .padding(.top, 42)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)

      SidebarGroupTitle("任务")

      VStack(spacing: 3) {
        ForEach(MainWindowModel.Filter.allCases) { filter in
          SidebarFilterRow(
            filter: filter,
            count: model.count(for: filter),
            selected: model.selectedSection == .tasks(filter)
          ) {
            model.select(.tasks(filter))
          }
        }
      }
      .padding(.horizontal, 16)

      Divider()
        .padding(.horizontal, 19)
        .padding(.vertical, 14)

      SidebarGroupTitle("设置")

      VStack(spacing: 3) {
        ForEach(MainWindowModel.PreferencesSection.allCases) { section in
          SidebarPreferenceRow(
            section: section,
            selected: model.selectedSection == .preferences(section)
          ) {
            model.select(.preferences(section))
          }
        }
      }
      .padding(.horizontal, 16)

      Spacer()

      Button {
        model.openDownloadDirectory()
      } label: {
        Label("下载目录", systemImage: "folder")
          .font(.system(size: 13, weight: .medium))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 20)
      .padding(.bottom, 22)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.regularMaterial)
        .shadow(color: .black.opacity(0.045), radius: 14, x: 0, y: 7)
        .padding(10)
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 22) {
      if let task = model.selectedTask {
        TaskDetailView(task: task, model: model)
      } else {
        header

        switch model.selectedSection {
        case .preferences(let section):
          PreferencesView(model: model, section: section)
        case .tasks:
          if let errorText = model.errorText {
            ErrorBanner(text: errorText)
          }

          if model.filteredTasks.isEmpty {
            emptyState
          } else {
            taskList
          }
        }
      }
    }
    .padding(.top, 34)
    .padding(.leading, 30)
    .padding(.trailing, 28)
    .padding(.bottom, 28)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text(titleText)
          .font(.system(size: 26, weight: .semibold))
          .foregroundStyle(.primary)

        Text(subtitleText)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      if case .tasks = model.selectedSection {
        SearchField(text: $model.searchText)
          .frame(width: 240)
      }

      if case .tasks = model.selectedSection {
        Menu {
          Picker("排序", selection: $model.taskSort) {
            ForEach(MainWindowModel.TaskSort.allCases) { sort in
              Text(sort.title).tag(sort)
            }
          }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 34)
        .help("任务排序")

        Button {
          model.setTaskSelection(!model.isSelectingTasks)
        } label: {
          Image(systemName: model.isSelectingTasks ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(model.isSelectingTasks ? .teal : nil)
        .help(model.isSelectingTasks ? "结束选择" : "批量选择")
      }

      if case .tasks = model.selectedSection {
        Button {
          model.showingAddTask = true
        } label: {
          Label("新建", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.teal)
      }

      if case .tasks = model.selectedSection {
        Button {
          Task { await model.refresh() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help("刷新")

        Menu {
          Button {
            Task { await model.clearCompletedTasks() }
          } label: {
            Label("清理已完成任务", systemImage: "checkmark.circle")
          }
          .disabled(model.count(for: .completed) == 0)
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 34)
        .help("更多任务操作")
      }
    }
  }

  private var titleText: String {
    switch model.selectedSection {
    case .preferences(let section):
      return section.title
    case .tasks(let filter):
      return filter.title
    }
  }

  private var subtitleText: String {
    switch model.selectedSection {
    case .preferences(let section):
      return model.settingsSaved ? "设置已保存，部分项目将在引擎重启后生效" : section.subtitle
    case .tasks:
      return model.summaryText
    }
  }

  private var taskList: some View {
    VStack(spacing: 10) {
      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach(model.filteredTasks) { task in
            TaskCard(task: task, model: model)
          }
        }
        .padding(14)
      }
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor).opacity(0.74))
      }

      if model.isSelectingTasks {
        TaskSelectionBar(model: model)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 42, weight: .regular))
        .foregroundStyle(.tertiary)

      Text(model.searchText.isEmpty ? "这里还没有任务" : "没有匹配的任务")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.secondary)

      Text(model.searchText.isEmpty ? "添加一个链接后，下载会出现在这里。" : "换个关键词试试。")
        .font(.system(size: 13))
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct SidebarFilterRow: View {
  let filter: MainWindowModel.Filter
  let count: Int
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        ZStack {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(filter.color.gradient)

          Image(systemName: filter.systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)

        Text(filter.title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(selected ? .primary : .secondary)

        Spacer()

        Text("\(count)")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(selected ? .white : .secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background {
            Capsule()
              .fill(selected ? Color.white.opacity(0.26) : Color.primary.opacity(0.06))
          }
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(selected ? filter.color.opacity(0.22) : Color.clear)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .stroke(selected ? filter.color.opacity(0.3) : Color.clear, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
  }
}

private struct SidebarGroupTitle: View {
  let title: String

  init(_ title: String) {
    self.title = title
  }

  var body: some View {
    Text(title.uppercased())
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(.tertiary)
      .padding(.horizontal, 20)
      .padding(.bottom, 6)
  }
}

private struct SidebarPreferenceRow: View {
  let section: MainWindowModel.PreferencesSection
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        ZStack {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(section.color.gradient)

          Image(systemName: section.systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)

        Text(section.title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(selected ? .primary : .secondary)

        Spacer()
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(selected ? section.color.opacity(0.16) : Color.clear)
      }
    }
    .buttonStyle(.plain)
  }
}

private struct SearchField: View {
  @Binding var text: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField("Search", text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 15))
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor))
    }
  }
}

private struct PreferencesView: View {
  @ObservedObject var model: MainWindowModel
  let section: MainWindowModel.PreferencesSection

  @State private var trackerExpanded = false

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        Group {
          switch section {
          case .general:
            generalSettings
          case .download:
            downloadSettings
          case .bittorrent:
            bittorrentSettings
          case .connection:
            connectionSettings
          }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.trailing, 10)
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)

      Divider()

      HStack(spacing: 10) {
        Text("设置保存在 Motrix Native 的独立配置目录")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)

        Spacer()

        Button("还原") {
          model.resetSettings()
        }

        Button("保存更改") {
          model.saveSettings()
        }
        .buttonStyle(.borderedProminent)
        .tint(.teal)
      }
      .padding(.top, 14)
    }
  }

  private var generalSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      PreferenceGroup(title: "应用") {
        preferenceToggle(
          "登录时打开",
          subtitle: "登录 Mac 后自动启动 Motrix Native",
          image: "power",
          color: .blue,
          isOn: $model.settings.openAtLogin
        )
        PreferenceDivider()
        preferenceToggle(
          "下载完成后通知",
          subtitle: "任务完成时发送系统通知",
          image: "bell.fill",
          color: .orange,
          isOn: $model.settings.taskNotification
        )
      }

      PreferenceGroup(title: "任务行为") {
        preferenceToggle(
          "新增任务后默认暂停",
          subtitle: "创建任务后等待手动开始",
          image: "pause.circle.fill",
          color: .purple,
          isOn: $model.settings.pause
        )
        PreferenceDivider()
        preferenceToggle(
          "删除任务时不再确认",
          subtitle: "移除任务前跳过确认步骤",
          image: "trash.fill",
          color: .red,
          isOn: $model.settings.noConfirmBeforeDeleteTask
        )
      }
    }
  }

  private var downloadSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      PreferenceGroup(title: "保存位置") {
        PreferenceRow(
          title: "默认下载文件夹",
          subtitle: model.settings.downloadDirectory,
          image: "folder.fill",
          color: .blue
        ) {
          Button {
            model.chooseDownloadDirectory()
          } label: {
            Image(systemName: "ellipsis")
          }
          .buttonStyle(.bordered)
          .help("选择下载文件夹")
        }
      }

      PreferenceGroup(title: "速度限制", footer: "0 表示不限制。可输入 20M、500K 等 aria2 支持的格式。") {
        PreferenceRow(title: "下载速度", subtitle: "所有任务的总下载上限", image: "arrow.down", color: .teal) {
          limitField($model.settings.maxOverallDownloadLimit)
        }
        PreferenceDivider()
        PreferenceRow(title: "上传速度", subtitle: "所有任务的总上传上限", image: "arrow.up", color: .indigo) {
          limitField($model.settings.maxOverallUploadLimit)
        }
      }

      PreferenceGroup(title: "任务调度") {
        preferenceToggle(
          "智能并发",
          subtitle: "为大文件自动探测并记住每个服务器的最佳连接数",
          image: "speedometer",
          color: .teal,
          isOn: $model.settings.adaptiveConnections
        )
        PreferenceDivider()
        preferenceToggle(
          "断点续传",
          subtitle: "重新启动后继续未完成的任务",
          image: "arrow.clockwise",
          color: .green,
          isOn: $model.settings.continueDownloads
        )
        PreferenceDivider()
        preferenceStepper("同时下载", subtitle: "允许同时运行的任务数", image: "square.stack.3d.up.fill", color: .blue, value: $model.settings.maxConcurrentDownloads, range: 1...50)
        PreferenceDivider()
        preferenceNumberField("单服务器连接数", subtitle: "手动模式使用值，也是智能并发的上限", image: "server.rack", color: .orange, value: $model.settings.maxConnectionPerServer, range: 1...128)
        PreferenceDivider()
        preferenceNumberField("任务分片上限", subtitle: "每个任务允许的并发分片上限", image: "square.grid.3x3.fill", color: .purple, value: $model.settings.split, range: 1...128)
      }
    }
  }

  private var bittorrentSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      PreferenceGroup(title: "BitTorrent") {
        preferenceToggle(
          "保存磁力链接元数据",
          subtitle: "将获取到的元数据保存为 torrent 文件",
          image: "doc.badge.arrow.up.fill",
          color: .blue,
          isOn: $model.settings.btSaveMetadata
        )
        PreferenceDivider()
        preferenceToggle(
          "强制加密",
          subtitle: "仅连接支持加密的 BT 客户端",
          image: "lock.fill",
          color: .indigo,
          isOn: $model.settings.btForceEncryption
        )
      }

      PreferenceGroup(title: "做种") {
        preferenceToggle(
          "下载完成后做种",
          subtitle: "关闭后 BT 下载完成便立即结束任务",
          image: "arrow.up.circle.fill",
          color: .indigo,
          isOn: Binding(
            get: { model.settings.seedingEnabled },
            set: { enabled in
              model.settings.seedingEnabled = enabled
              if enabled && model.settings.seedTime == 0 {
                model.settings.seedTime = 60
              }
            }
          )
        )
        PreferenceDivider()
        preferenceStepper("分享率", subtitle: "达到该比例后停止做种，0 表示不限制", image: "arrow.triangle.2.circlepath", color: .green, value: $model.settings.seedRatio, range: 0...100)
          .disabled(!model.settings.seedingEnabled)
          .opacity(model.settings.seedingEnabled ? 1 : 0.45)
        PreferenceDivider()
        preferenceStepper("做种时间", subtitle: "最长持续做种的分钟数", image: "clock.fill", color: .orange, value: $model.settings.seedTime, range: 1...10080)
          .disabled(!model.settings.seedingEnabled)
          .opacity(model.settings.seedingEnabled ? 1 : 0.45)
      }

      PreferenceGroup(title: "Tracker 服务器", footer: "支持使用逗号或换行分隔服务器地址。") {
        Button {
          withAnimation(.easeInOut(duration: 0.18)) {
            trackerExpanded.toggle()
          }
        } label: {
          HStack(spacing: 12) {
            PreferenceIcon(image: "antenna.radiowaves.left.and.right", color: .teal)

            VStack(alignment: .leading, spacing: 3) {
              Text("自定义 Tracker 列表")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
              Text(trackerCount == 0 ? "未配置服务器" : "已配置 \(trackerCount) 个服务器")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(trackerExpanded ? "收起" : "编辑")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.tertiary)
              .rotationEffect(.degrees(trackerExpanded ? 90 : 0))
          }
          .padding(14)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if trackerExpanded {
          PreferenceDivider()
          TextEditor(text: $model.settings.btTracker)
            .font(.system(size: 11, design: .monospaced))
            .frame(minHeight: 150)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
            }
            .padding(14)
            .padding(.top, -4)
        }
      }
    }
  }

  private var connectionSettings: some View {
    VStack(alignment: .leading, spacing: 24) {
      PreferenceGroup(title: "RPC", footer: "RPC 设置发生变化后，需要从状态栏的高级菜单重启引擎。") {
        PreferenceRow(title: "监听端口", subtitle: "本地客户端连接 aria2 的端口", image: "dot.radiowaves.left.and.right", color: .blue) {
          PortField(value: $model.settings.rpcPort)
        }
        PreferenceDivider()
        PreferenceRow(title: "授权密钥", subtitle: "用于保护 JSON-RPC 连接", image: "key.fill", color: .orange) {
          RPCSecretField(text: $model.settings.rpcSecret)
        }
      }

      PreferenceGroup(title: "传入连接") {
        PreferenceRow(title: "BT 监听端口", subtitle: "接收 BitTorrent 对等连接", image: "arrow.left.arrow.right.circle.fill", color: .purple) {
          PortField(value: $model.settings.listenPort)
        }
        PreferenceDivider()
        PreferenceRow(title: "DHT 监听端口", subtitle: "用于 DHT 网络发现", image: "network", color: .teal) {
          PortField(value: $model.settings.dhtListenPort)
        }
      }

      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "info.circle.fill")
          .foregroundStyle(.blue)
        Text("首次启动会继承 Motrix 的端口和密钥，之后由 Motrix Native 独立保存。修改后保存，再从状态栏的高级菜单重启引擎即可生效。")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(14)
      .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var trackerCount: Int {
    model.settings.btTracker
      .split { $0 == "," || $0 == "\n" }
      .filter { !String($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .count
  }

  private func preferenceToggle(
    _ title: String,
    subtitle: String,
    image: String,
    color: Color,
    isOn: Binding<Bool>
  ) -> some View {
    PreferenceRow(title: title, subtitle: subtitle, image: image, color: color) {
      Toggle("", isOn: isOn)
        .labelsHidden()
        .toggleStyle(.switch)
    }
  }

  private func preferenceStepper(
    _ title: String,
    subtitle: String,
    image: String,
    color: Color,
    value: Binding<Int>,
    range: ClosedRange<Int>
  ) -> some View {
    PreferenceRow(title: title, subtitle: subtitle, image: image, color: color) {
      Stepper(value: value, in: range) {
        Text("\(value.wrappedValue)")
          .font(.system(size: 13, weight: .medium, design: .rounded))
          .monospacedDigit()
          .frame(width: 54, alignment: .trailing)
      }
      .fixedSize()
    }
  }

  private func preferenceNumberField(
    _ title: String,
    subtitle: String,
    image: String,
    color: Color,
    value: Binding<Int>,
    range: ClosedRange<Int>
  ) -> some View {
    PreferenceRow(title: title, subtitle: subtitle, image: image, color: color) {
      IntegerStepperField(value: value, range: range)
    }
  }

  private func limitField(_ value: Binding<String>) -> some View {
    HStack(spacing: 6) {
      TextField("0", text: value)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 92)
      Text("/s")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
  }
}

private struct PreferenceGroup<Content: View>: View {
  let title: String
  let footer: String?
  let content: Content

  init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.footer = footer
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
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.primary.opacity(0.055), lineWidth: 1)
      }

      if let footer {
        Text(footer)
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 4)
      }
    }
  }
}

private struct PreferenceRow<Trailing: View>: View {
  let title: String
  let subtitle: String
  let image: String
  let color: Color
  let trailing: Trailing

  init(
    title: String,
    subtitle: String,
    image: String,
    color: Color,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.subtitle = subtitle
    self.image = image
    self.color = color
    self.trailing = trailing()
  }

  var body: some View {
    HStack(spacing: 12) {
      PreferenceIcon(image: image, color: color)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.primary)
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer(minLength: 18)
      trailing
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
  }
}

private struct PreferenceIcon: View {
  let image: String
  let color: Color

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(color.gradient)
      Image(systemName: image)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
    }
    .frame(width: 28, height: 28)
  }
}

private struct PreferenceDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 54)
  }
}

private struct PortField: View {
  @Binding var value: Int
  @State private var text: String
  @FocusState private var isFocused: Bool

  init(value: Binding<Int>) {
    self._value = value
    self._text = State(initialValue: String(value.wrappedValue))
  }

  var body: some View {
    TextField("1024-65535", text: $text)
      .textFieldStyle(.roundedBorder)
      .font(.system(size: 13, design: .monospaced))
      .multilineTextAlignment(.trailing)
      .frame(width: 118)
      .focused($isFocused)
      .onChange(of: text) { _, newValue in
        let digits = newValue.filter(\.isNumber)
        if digits != newValue {
          text = digits
          return
        }

        if let port = Int(digits), (1024...65535).contains(port) {
          value = port
        }
      }
      .onChange(of: value) { _, newValue in
        if !isFocused {
          text = String(newValue)
        }
      }
      .onChange(of: isFocused) { _, focused in
        if !focused {
          commit()
        }
      }
      .onSubmit(commit)
  }

  private func commit() {
    guard let entered = Int(text) else {
      text = String(value)
      return
    }

    value = min(65535, max(1024, entered))
    text = String(value)
  }
}

private struct IntegerStepperField: View {
  @Binding var value: Int
  let range: ClosedRange<Int>

  @State private var text: String
  @FocusState private var isFocused: Bool

  init(value: Binding<Int>, range: ClosedRange<Int>) {
    self._value = value
    self.range = range
    self._text = State(initialValue: String(value.wrappedValue))
  }

  var body: some View {
    HStack(spacing: 6) {
      TextField("\(range.lowerBound)-\(range.upperBound)", text: $text)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13, design: .monospaced))
        .multilineTextAlignment(.trailing)
        .frame(width: 72)
        .focused($isFocused)
        .onChange(of: text) { _, newValue in
          let digits = newValue.filter(\.isNumber)
          if digits != newValue {
            text = digits
            return
          }

          if let entered = Int(digits), range.contains(entered) {
            value = entered
          }
        }
        .onChange(of: isFocused) { _, focused in
          if !focused {
            commit()
          }
        }
        .onSubmit(commit)

      Stepper("", value: $value, in: range)
        .labelsHidden()
        .fixedSize()
        .onChange(of: value) { _, newValue in
          text = String(newValue)
        }
    }
  }

  private func commit() {
    guard let entered = Int(text) else {
      text = String(value)
      return
    }

    value = min(range.upperBound, max(range.lowerBound, entered))
    text = String(value)
  }
}

private struct RPCSecretField: View {
  @Binding var text: String
  @State private var isRevealed = false

  var body: some View {
    HStack(spacing: 0) {
      Group {
        if isRevealed {
          TextField("未设置", text: $text)
        } else {
          SecureField("未设置", text: $text)
        }
      }
      .textFieldStyle(.plain)
      .font(.system(size: 13, design: .monospaced))
      .padding(.horizontal, 9)

      Divider()
        .frame(height: 20)

      secretButton(
        isRevealed ? "eye.slash" : "eye",
        help: isRevealed ? "隐藏密钥" : "显示密钥"
      ) {
        isRevealed.toggle()
      }

      Divider()
        .frame(height: 20)

      secretButton("dice.fill", help: "生成随机密钥") {
        text = Self.randomSecret()
      }
    }
    .frame(width: 278, height: 30)
    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(Color.primary.opacity(0.14), lineWidth: 1)
    }
  }

  private func secretButton(_ image: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: image)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 34, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  private static func randomSecret() -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    var generator = SystemRandomNumberGenerator()
    return String((0..<32).compactMap { _ in alphabet.randomElement(using: &generator) })
  }
}

private struct TaskDetailView: View {
  let task: Aria2Task
  @ObservedObject var model: MainWindowModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      detailHeader

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          progressSection

          if task.numPieces > 0 {
            pieceMapSection
          }

          HStack(alignment: .top, spacing: 18) {
            DetailSection(title: "传输") {
              DetailRow(title: "下载速度", value: Formatting.speed(task.downloadSpeed))
              DetailDivider()
              DetailRow(title: "上传速度", value: Formatting.speed(task.uploadSpeed))
              DetailDivider()
              DetailRow(title: "已下载", value: Formatting.bytes(task.completedLength))
              DetailDivider()
              DetailRow(title: "已上传", value: Formatting.bytes(task.uploadLength))
              if task.isBitTorrent {
                DetailDivider()
                DetailRow(title: "分享率", value: shareRatioText)
              }
              DetailDivider()
              DetailRow(title: "活动连接", value: "\(task.connections)")
            }
            .frame(maxWidth: .infinity)

            DetailSection(title: "任务信息") {
              DetailRow(title: "类型", value: task.isBitTorrent ? "BitTorrent" : "HTTP / FTP")
              DetailDivider()
              DetailRow(title: "数据块", value: task.numPieces > 0 ? "\(task.numPieces) × \(Formatting.bytes(task.pieceLength))" : "-")
              DetailDivider()
              DetailRow(title: "任务分片上限", value: effectiveOption("split"))
              DetailDivider()
              DetailRow(title: "单服务器连接上限", value: effectiveOption("max-connection-per-server"))
              DetailDivider()
              DetailRow(title: "服务器", value: task.sourceHost ?? "-")
              DetailDivider()
              DetailRow(title: "GID", value: task.id, monospaced: true)
            }
            .frame(maxWidth: .infinity)
          }

          if task.status == "error" {
            HStack(alignment: .top, spacing: 10) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
              VStack(alignment: .leading, spacing: 3) {
                Text("任务错误 \(task.errorCode)")
                  .font(.system(size: 13, weight: .semibold))
                Text(task.errorMessage.isEmpty ? "aria2 未提供详细错误信息" : task.errorMessage)
                  .font(.system(size: 12))
                  .foregroundStyle(.secondary)
              }
              Spacer()
            }
            .padding(14)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
          }

          if task.isBitTorrent {
            bitTorrentSummary
            trackerSection
            peerSection
          }

          DetailSection(title: task.fileDetails.count > 1 ? "文件（\(task.fileDetails.count)）" : "文件") {
            ForEach(Array(task.fileDetails.enumerated()), id: \.element.id) { index, file in
              TaskFileRow(file: file)
              if index < task.fileDetails.count - 1 {
                DetailDivider()
              }
            }
          }

          DetailSection(title: "位置与来源") {
            DetailRow(title: "保存位置", value: task.directory.isEmpty ? (task.primaryFileURL?.path ?? "-") : task.directory)
            if let sourceURI = task.sourceURI {
              DetailDivider()
              DetailRow(title: "来源", value: sourceURI)
            }
          }
        }
        .padding(.trailing, 10)
        .padding(.bottom, 24)
      }
    }
  }

  private var detailHeader: some View {
    HStack(spacing: 14) {
      Button {
        model.closeDetails()
      } label: {
        Image(systemName: "chevron.left")
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .help("返回任务列表")

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 9) {
          Text(task.name)
            .font(.system(size: 24, weight: .semibold))
            .lineLimit(1)
          StatusPill(status: task.status, isSeeding: task.isSeeding)
        }
        Text(task.primaryFileURL?.deletingLastPathComponent().path ?? task.id)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      if task.status == "active" {
        Button {
          Task { await model.pause(task) }
        } label: {
          Label("暂停", systemImage: "pause.fill")
        }
      } else if task.status == "paused" || task.status == "waiting" {
        Button {
          Task { await model.resume(task) }
        } label: {
          Label("继续", systemImage: "play.fill")
        }
      }

      Button {
        model.reveal(task)
      } label: {
        Image(systemName: "folder")
      }
      .help("显示文件位置")

      Menu {
        Button("复制 GID") {
          model.copyGID(task)
        }
        if task.status == "waiting" || task.status == "paused" {
          Menu("队列优先级") {
            Button("移到队首") { Task { await model.moveInQueue(task, .top) } }
            Button("上移一位") { Task { await model.moveInQueue(task, .up) } }
            Button("下移一位") { Task { await model.moveInQueue(task, .down) } }
            Button("移到队尾") { Task { await model.moveInQueue(task, .bottom) } }
          }
        }
        Divider()
        Button("移除任务", role: .destructive) {
          Task { await model.remove(task) }
        }
        Button("移除并将文件移到废纸篓", role: .destructive) {
          Task { await model.remove(task, deletingFiles: true) }
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .frame(width: 30)
    }
  }

  private var progressSection: some View {
    HStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(statusColor.opacity(0.14))
        Image(systemName: task.isSeeding ? "arrow.up.circle.fill" : task.status == "complete" ? "checkmark.circle.fill" : "arrow.down.circle.fill")
          .font(.system(size: 25, weight: .semibold))
          .foregroundStyle(statusColor)
      }
      .frame(width: 54, height: 54)

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(task.isSeeding ? "下载完成，正在做种" : task.localizedStatus)
            .font(.system(size: 14, weight: .semibold))
          Spacer()
          Text("\(Int((task.progress * 100).rounded()))%")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .monospacedDigit()
        }

        ProgressView(value: task.progress)
          .tint(statusColor)

        Text("\(Formatting.bytes(task.completedLength)) / \(Formatting.bytes(task.totalLength))")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.primary.opacity(0.055), lineWidth: 1)
    }
  }

  private var statusColor: Color {
    if task.isSeeding { return .indigo }
    switch task.status {
    case "active": return .teal
    case "paused": return .orange
    case "complete": return .green
    case "error": return .red
    default: return .secondary
    }
  }

  private var shareRatioText: String {
    guard task.completedLength > 0 else { return "0.00" }
    return String(format: "%.2f", Double(task.uploadLength) / Double(task.completedLength))
  }

  private var pieceMapSection: some View {
    DetailSection(title: "数据块分布") {
      PieceMapView(task: task)
    }
  }

  private func effectiveOption(_ key: String) -> String {
    model.selectedTaskOptions[key] ?? "读取中..."
  }

  private var bitTorrentSummary: some View {
    DetailSection(title: "BitTorrent 网络") {
      DetailRow(title: "Info Hash", value: task.infoHash.isEmpty ? "-" : task.infoHash, monospaced: true)
      DetailDivider()
      DetailRow(title: "Tracker", value: "\(task.trackers.count)")
      DetailDivider()
      DetailRow(title: "Peer", value: "\(model.selectedPeers.count)")
      DetailDivider()
      DetailRow(title: "做种节点", value: "\(model.selectedPeers.filter(\.isSeeder).count)")
    }
  }

  private var trackerSection: some View {
    DetailSection(title: "Tracker（\(task.trackers.count)）") {
      if task.trackers.isEmpty {
        DetailEmptyRow(text: "当前任务没有可用的 Tracker 信息")
      } else {
        ForEach(Array(task.trackers.prefix(8).enumerated()), id: \.offset) { index, tracker in
          DetailTextRow(image: "antenna.radiowaves.left.and.right", text: tracker)
          if index < min(task.trackers.count, 8) - 1 {
            DetailDivider()
          }
        }

        if task.trackers.count > 8 {
          DetailDivider()
          DetailEmptyRow(text: "另有 \(task.trackers.count - 8) 个 Tracker")
        }
      }
    }
  }

  private var peerSection: some View {
    DetailSection(title: "Peer（\(model.selectedPeers.count)）") {
      if model.selectedPeers.isEmpty {
        DetailEmptyRow(text: task.status == "active" ? "正在等待对等节点" : "任务未活动，暂无 Peer 信息")
      } else {
        ForEach(Array(model.selectedPeers.prefix(20).enumerated()), id: \.offset) { index, peer in
          PeerRow(peer: peer)
          if index < min(model.selectedPeers.count, 20) - 1 {
            DetailDivider()
          }
        }

        if model.selectedPeers.count > 20 {
          DetailDivider()
          DetailEmptyRow(text: "另有 \(model.selectedPeers.count - 20) 个 Peer")
        }
      }
    }
  }
}

private struct DetailSection<Content: View>: View {
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

private struct DetailRow: View {
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

private struct DetailDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 14)
  }
}

private struct PieceMapView: View {
  let task: Aria2Task

  private let cellSize: CGFloat = 9
  private let spacing: CGFloat = 3
  private let maximumSamples = 480

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      if samples.isEmpty {
        Text("aria2 暂未提供数据块状态")
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
        .accessibilityLabel("数据块完成分布")
        .accessibilityValue("已完成 \(completedPieceCount) 个，共 \(task.numPieces) 个")

        HStack(spacing: 16) {
          PieceLegend(color: .teal, title: "已完成")
          PieceLegend(color: Color.primary.opacity(0.1), title: "未完成")
          if task.numPieces > maximumSamples {
            PieceLegend(color: .teal.opacity(0.46), title: "混合区块")
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

private struct DetailEmptyRow: View {
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

private struct DetailTextRow: View {
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

private struct PeerRow: View {
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
        Text(peer.isSeeder ? "做种节点" : peer.isChoking ? "已限流" : "正在传输")
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

private struct TaskFileRow: View {
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

private struct TaskCard: View {
  let task: Aria2Task
  @ObservedObject var model: MainWindowModel

  var body: some View {
    HStack(spacing: 0) {
      Button {
        if model.isSelectingTasks {
          model.toggleTaskSelection(task)
        } else {
          model.showDetails(task)
        }
      } label: {
        HStack(spacing: 16) {
          if model.isSelectingTasks {
            Image(systemName: model.selectedTaskIDs.contains(task.id) ? "checkmark.circle.fill" : "circle")
              .font(.system(size: 17, weight: .medium))
              .foregroundStyle(model.selectedTaskIDs.contains(task.id) ? .teal : .secondary)
          }

          taskIcon

          VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
              Text(task.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

              StatusPill(status: task.status, isSeeding: task.isSeeding)
            }

            Text(task.primaryFileURL?.deletingLastPathComponent().path ?? task.id)
              .font(.system(size: 12))
              .foregroundStyle(.tertiary)
              .lineLimit(1)

            HStack(spacing: 10) {
              ProgressView(value: task.progress)
                .tint(.teal)
                .frame(maxWidth: 280)

              Text("\(Int((task.progress * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
          }

          Spacer(minLength: 16)

          VStack(alignment: .trailing, spacing: 5) {
            Text(task.downloadSpeed > 0 ? Formatting.speed(task.downloadSpeed) : "空闲")
              .font(.system(size: 13, weight: .medium, design: .rounded))
              .foregroundStyle(task.downloadSpeed > 0 ? .primary : .secondary)

            Text("\(Formatting.bytes(task.completedLength)) / \(Formatting.bytes(task.totalLength))")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
          }
          .frame(width: 170, alignment: .trailing)

          if !model.isSelectingTasks {
            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.leading, 16)
        .padding(.vertical, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if !model.isSelectingTasks {
        HStack(spacing: 4) {
          if task.status == "active" {
            iconButton("pause.fill", help: "暂停") {
              Task { await model.pause(task) }
            }
          } else if task.status == "paused" || task.status == "waiting" {
            iconButton("play.fill", help: "继续") {
              Task { await model.resume(task) }
            }
          }

          iconButton("folder", help: "显示位置") {
            model.reveal(task)
          }

          iconButton("trash", help: "移除") {
            Task { await model.remove(task) }
          }
        }
        .padding(.trailing, 16)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(model.selectedTaskIDs.contains(task.id) ? Color.teal.opacity(0.09) : Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.035), radius: 8, x: 0, y: 3)
    }
    .contextMenu {
      Button("查看详情") {
        model.showDetails(task)
      }

      Divider()

      if task.status == "active" {
        Button("暂停") {
          Task { await model.pause(task) }
        }
      } else if task.status == "paused" || task.status == "waiting" {
        Button("继续") {
          Task { await model.resume(task) }
        }
      }

      Button("显示文件位置") {
        model.reveal(task)
      }

      if task.status == "waiting" || task.status == "paused" {
        Menu("队列优先级") {
          Button("移到队首") { Task { await model.moveInQueue(task, .top) } }
          Button("上移一位") { Task { await model.moveInQueue(task, .up) } }
          Button("下移一位") { Task { await model.moveInQueue(task, .down) } }
          Button("移到队尾") { Task { await model.moveInQueue(task, .bottom) } }
        }
      }

      Divider()

      Button("移除", role: .destructive) {
        Task { await model.remove(task) }
      }
      Button("移除并将文件移到废纸篓", role: .destructive) {
        Task { await model.remove(task, deletingFiles: true) }
      }
    }
  }

  private var taskIcon: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(statusColor.opacity(0.16))

      Image(systemName: task.isSeeding ? "arrow.up" : task.status == "complete" ? "checkmark" : "arrow.down")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(statusColor)
    }
    .frame(width: 46, height: 46)
  }

  private var statusColor: Color {
    if task.isSeeding { return .indigo }
    switch task.status {
    case "active": return .teal
    case "paused": return .orange
    case "complete": return .green
    case "error": return .red
    default: return .secondary
    }
  }

  private func iconButton(_ image: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      ZStack {
        Circle()
          .fill(Color.primary.opacity(0.055))

        Image(systemName: image)
          .foregroundStyle(.secondary)
      }
      .frame(width: 30, height: 30)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}

private struct TaskSelectionBar: View {
  @ObservedObject var model: MainWindowModel

  var body: some View {
    HStack(spacing: 10) {
      Text("已选择 \(model.selectedTaskIDs.count) 项")
        .font(.system(size: 13, weight: .semibold))

      Button(model.selectedTaskIDs.count == model.filteredTasks.count ? "取消全选" : "全选") {
        if model.selectedTaskIDs.count == model.filteredTasks.count {
          model.selectedTaskIDs.removeAll()
        } else {
          model.selectAllVisibleTasks()
        }
      }
      .buttonStyle(.link)

      Spacer()

      Button {
        Task { await model.pauseSelectedTasks() }
      } label: {
        Label("暂停", systemImage: "pause.fill")
      }
      .disabled(model.selectedTaskIDs.isEmpty)

      Button {
        Task { await model.resumeSelectedTasks() }
      } label: {
        Label("继续", systemImage: "play.fill")
      }
      .disabled(model.selectedTaskIDs.isEmpty)

      Menu {
        Button("仅移除任务", role: .destructive) {
          Task { await model.removeSelectedTasks(deletingFiles: false) }
        }
        Button("移除并将文件移到废纸篓", role: .destructive) {
          Task { await model.removeSelectedTasks(deletingFiles: true) }
        }
      } label: {
        Label("移除", systemImage: "trash")
      }
      .disabled(model.selectedTaskIDs.isEmpty)

      Button("完成") {
        model.endTaskSelection()
      }
      .buttonStyle(.borderedProminent)
      .tint(.teal)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
    }
  }
}

private struct StatusPill: View {
  let status: String
  var isSeeding = false

  var body: some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background {
        Capsule()
          .fill(color.opacity(0.13))
      }
  }

  private var title: String {
    if isSeeding { return "做种中" }
    switch status {
    case "active": return "下载中"
    case "waiting": return "等待"
    case "paused": return "暂停"
    case "complete": return "完成"
    case "error": return "错误"
    case "removed": return "已移除"
    default: return status
    }
  }

  private var color: Color {
    switch status {
    case "active": return .teal
    case "waiting": return .secondary
    case "paused": return .orange
    case "complete": return .green
    case "error": return .red
    default: return .secondary
    }
  }
}

private struct ErrorBanner: View {
  let text: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)

      Text(text)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)

      Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.orange.opacity(0.1))
    }
  }
}

private struct AddTaskSheet: View {
  @ObservedObject var model: MainWindowModel
  @Environment(\.dismiss) private var dismiss

  @State private var urlText = ""
  @State private var directoryPath: String
  @State private var outputName = ""
  @State private var headers = ""
  @State private var cookie = ""
  @State private var referer = ""
  @State private var checksum = ""
  @State private var pauseAtStart: Bool
  @State private var advancedExpanded = false
  @State private var preparedTorrent: PreparedTorrent?
  @State private var selectedFileIDs = Set<String>()
  @State private var isPreparingTorrent = false
  @State private var committed = false

  init(model: MainWindowModel) {
    self.model = model
    self._directoryPath = State(initialValue: model.defaultDownloadDirectory.path)
    self._pauseAtStart = State(initialValue: model.defaultPauseAtStart)
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 4) {
            Text("新建任务")
              .font(.system(size: 22, weight: .semibold))

            Text("添加链接，或者拖入 torrent 后选择需要的文件。")
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("下载链接")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(.secondary)

            TextField("https:// 或 magnet:", text: $urlText, axis: .vertical)
              .textFieldStyle(.roundedBorder)
              .lineLimit(3, reservesSpace: true)
              .disabled(preparedTorrent != nil)
          }

          directoryRow
          torrentPicker

          if let preparedTorrent {
            torrentFileSelection(preparedTorrent)
          }

          DisclosureGroup("高级选项", isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: 12) {
              labeledField("文件名", placeholder: "留空则使用服务器提供的名称", text: $outputName)
                .disabled(preparedTorrent != nil)
              labeledField("Referer", placeholder: "https://example.com/", text: $referer)
              labeledField("Cookie", placeholder: "name=value; ...", text: $cookie)
              labeledField("校验值", placeholder: "sha-256=...", text: $checksum)

              VStack(alignment: .leading, spacing: 6) {
                Text("请求头")
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(.secondary)
                TextEditor(text: $headers)
                  .font(.system(size: 11, design: .monospaced))
                  .frame(minHeight: 76)
                  .scrollContentBackground(.hidden)
                  .padding(8)
                  .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                  .overlay {
                    RoundedRectangle(cornerRadius: 6)
                      .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                  }
              }
            }
            .padding(.top, 12)
          }
          .font(.system(size: 13, weight: .medium))

          Toggle("创建后保持暂停", isOn: $pauseAtStart)
            .toggleStyle(.switch)
            .font(.system(size: 13, weight: .medium))
        }
        .padding(24)
      }

      Divider()

      HStack {
        Spacer()

        Button("取消") {
          cancel()
        }
        .keyboardShortcut(.cancelAction)

        Button("添加") {
          submit()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canSubmit || isPreparingTorrent)
      }
      .padding(16)
    }
    .frame(width: 620, height: preparedTorrent == nil ? 610 : 760)
    .onDisappear {
      guard !committed, let preparedTorrent else { return }
      Task { await model.discardPreparedTorrent(preparedTorrent) }
    }
  }

  private var directoryRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("保存位置")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        TextField("下载目录", text: $directoryPath)
          .textFieldStyle(.roundedBorder)
          .disabled(preparedTorrent != nil)

        Button {
          chooseDirectory()
        } label: {
          Image(systemName: "folder")
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .disabled(preparedTorrent != nil)
        .help("选择下载目录")
      }
    }
  }

  private var torrentPicker: some View {
    Button {
      chooseTorrent()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: preparedTorrent == nil ? "doc.badge.plus" : "doc.zipper")
          .font(.system(size: 20))
          .foregroundStyle(.purple)
          .frame(width: 30)

        VStack(alignment: .leading, spacing: 3) {
          Text(preparedTorrent?.sourceURL.lastPathComponent ?? "选择或拖入 torrent")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(isPreparingTorrent ? "正在读取文件列表..." : preparedTorrent == nil ? "下载开始前可以选择具体文件" : "点击可更换 torrent")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }

        Spacer()

        if isPreparingTorrent {
          ProgressView()
            .controlSize(.small)
        } else {
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
      }
      .padding(13)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .background(Color.purple.opacity(0.065), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color.purple.opacity(0.16), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .disabled(isPreparingTorrent)
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first(where: { $0.pathExtension.lowercased() == "torrent" }) else {
        return false
      }
      loadTorrent(url)
      return true
    }
  }

  private func torrentFileSelection(_ torrent: PreparedTorrent) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text("文件（\(torrent.files.count)）")
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Button("全选") {
          selectedFileIDs = Set(torrent.files.map(\.id))
        }
        .buttonStyle(.link)
        Button("全不选") {
          selectedFileIDs.removeAll()
        }
        .buttonStyle(.link)
      }

      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(torrent.files) { file in
            Toggle(isOn: Binding(
              get: { selectedFileIDs.contains(file.id) },
              set: { selected in
                if selected { selectedFileIDs.insert(file.id) }
                else { selectedFileIDs.remove(file.id) }
              }
            )) {
              HStack {
                Text(file.name)
                  .font(.system(size: 12))
                  .lineLimit(1)
                Spacer()
                Text(Formatting.bytes(file.length))
                  .font(.system(size: 11))
                  .foregroundStyle(.secondary)
              }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            if file.id != torrent.files.last?.id {
              Divider().padding(.leading, 32)
            }
          }
        }
      }
      .frame(maxHeight: 220)
      .background(Color(nsColor: .controlBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color.primary.opacity(0.07), lineWidth: 1)
      }
    }
  }

  private func labeledField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      TextField(placeholder, text: text)
        .textFieldStyle(.roundedBorder)
    }
  }

  private var canSubmit: Bool {
    preparedTorrent != nil || !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var options: NewDownloadOptions {
    NewDownloadOptions(
      directory: URL(fileURLWithPath: NSString(string: directoryPath).expandingTildeInPath),
      outputName: outputName,
      headers: headers,
      cookie: cookie,
      referer: referer,
      checksum: checksum,
      pauseAtStart: pauseAtStart
    )
  }

  private func chooseTorrent() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.torrent]

    if panel.runModal() == .OK {
      if let url = panel.url {
        loadTorrent(url)
      }
    }
  }

  private func loadTorrent(_ url: URL) {
    let previous = preparedTorrent
    preparedTorrent = nil
    selectedFileIDs.removeAll()
    urlText = ""
    isPreparingTorrent = true

    Task {
      if let previous {
        await model.discardPreparedTorrent(previous)
      }
      let prepared = await model.prepareTorrent(url, directory: options.directory)
      preparedTorrent = prepared
      selectedFileIDs = Set(prepared?.files.filter(\.isSelected).map(\.id) ?? [])
      isPreparingTorrent = false
    }
  }

  private func chooseDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = options.directory
    if panel.runModal() == .OK, let url = panel.url {
      directoryPath = url.path
    }
  }

  private func cancel() {
    let prepared = preparedTorrent
    preparedTorrent = nil
    if let prepared {
      Task { await model.discardPreparedTorrent(prepared) }
    }
    dismiss()
  }

  private func submit() {
    Task {
      let success: Bool
      if let preparedTorrent {
        success = await model.startPreparedTorrent(
          preparedTorrent,
          selectedFileIDs: selectedFileIDs,
          pauseAtStart: pauseAtStart
        )
      } else {
        success = await model.addLink(urlText, options: options)
      }

      if success {
        committed = true
        preparedTorrent = nil
        dismiss()
      }
    }
  }
}
