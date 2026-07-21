import SwiftUI

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

      SidebarGroupTitle(L10n.tr("sidebar.tasks"))

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

      SidebarGroupTitle(L10n.tr("sidebar.settings"))

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
        Label(L10n.tr("common.downloads_folder"), systemImage: "folder")
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
          Picker(L10n.tr("task.sort.label"), selection: $model.taskSort) {
            ForEach(MainWindowModel.TaskSort.allCases) { sort in
              Text(sort.title).tag(sort)
            }
          }
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 34)
        .help(L10n.tr("task.sort.help"))

        Button {
          model.setTaskSelection(!model.isSelectingTasks)
        } label: {
          Image(systemName: model.isSelectingTasks ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(model.isSelectingTasks ? .teal : nil)
        .help(model.isSelectingTasks ? L10n.tr("task.selection.finish") : L10n.tr("task.selection.start"))
      }

      if case .tasks = model.selectedSection {
        Button {
          model.showingAddTask = true
        } label: {
          Label(L10n.tr("task.action.new"), systemImage: "plus")
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
        .help(L10n.tr("action.refresh"))

        Menu {
          Button {
            Task { await model.clearCompletedTasks() }
          } label: {
            Label(L10n.tr("task.action.clear_completed"), systemImage: "checkmark.circle")
          }
          .disabled(model.count(for: .completed) == 0)
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 34)
        .help(L10n.tr("task.action.more"))
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
      return model.settingsSaved ? L10n.tr("preferences.saved_notice") : section.subtitle
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

      Text(model.searchText.isEmpty ? L10n.tr("task.empty.title") : L10n.tr("task.empty.search_title"))
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.secondary)

      Text(model.searchText.isEmpty ? L10n.tr("task.empty.subtitle") : L10n.tr("task.empty.search_subtitle"))
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

      TextField(L10n.tr("common.search"), text: $text)
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

