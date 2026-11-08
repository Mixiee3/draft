import SwiftUI
import EventKit
import DraftCore

struct PlannerHeader<Trailing: View>: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    var title: String
    var symbol: String
    var tint: Color? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            PillGroup { PillButton(symbol: "chevron.left", label: "Back (⌘[)") { model.goBack() } }
            Image(systemName: symbol).font(.system(size: DS.title3, weight: .semibold)).foregroundStyle(tint ?? t.accent).accessibilityHidden(true)
            Text(title).font(.system(size: DS.title2, weight: .bold)).foregroundStyle(t.text).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }
}

/// One task from any document: the checkbox changes the source block (one undo step).
struct TaskRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    @Environment(\.undoManager) var undo
    let doc: String
    let task: IndexedTask
    var showDue = true
    @State private var duePicker = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { model.setTask(doc, task.block, checked: !task.checked, undo: undo) } label: {
                Image(systemName: task.checked ? "checkmark.circle.fill" : "circle").font(.system(size: DS.headline)).foregroundStyle(task.checked ? t.accent : t.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.checked ? "Mark “\(task.text)” not done" : "Mark “\(task.text)” done")
            VStack(alignment: .leading, spacing: 2) {
                Text(task.text.isEmpty ? "Empty task" : task.text).font(.system(size: DS.body)).foregroundStyle(task.checked ? t.tertiary : t.text).strikethrough(task.checked)
                HStack(spacing: 6) {
                    if showDue, let d = task.dueDay {
                        let overdue = !task.checked && d < model.todayKey
                        Label(Day.label(d, today: model.todayKey) + (task.due!.count > 10 ? " " + String(task.due!.suffix(5)) : ""), systemImage: task.due!.count > 10 ? "clock" : "calendar")
                            .foregroundStyle(overdue ? Color.red : t.secondary)
                    }
                    Text(model.docTitle(doc)).foregroundStyle(t.tertiary)
                }.font(.system(size: DS.footnote)).labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
            Button { duePicker = true } label: { Image(systemName: "calendar.badge.clock").foregroundStyle(t.secondary) }
                .buttonStyle(.plain).help("Due date").accessibilityLabel("Set due date for “\(task.text)”")
                .popover(isPresented: $duePicker, arrowEdge: .trailing) { DuePicker(doc: doc, task: task) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.card))
        .contentShape(Rectangle())
        .onTapGesture { model.openBlock(doc, task.block) }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open in document") { model.openBlock(doc, task.block) }
    }
}

struct TasksView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    @State private var bucket: TaskBucket
    init(section: String?) { _bucket = State(initialValue: TaskBucket(rawValue: section ?? "") ?? .today) }

    var body: some View {
        let _ = model.indexTick
        let rows = model.tasks(bucket)
        VStack(spacing: 0) {
            PlannerHeader(title: "Tasks", symbol: "checklist") { EmptyView() }
            DraftSegmented("Show", selection: $bucket, options: TaskBucket.allCases.map { b in
                let n = b == .completed ? 0 : model.tasks(b).count
                return (b, b.title + (n > 0 ? " \(n)" : ""))
            }).padding(.horizontal, 18).padding(.bottom, 10).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Task list")
            if rows.isEmpty {
                EmptyLibrary(message: emptyText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) { ForEach(rows, id: \.task.block) { TaskRow(doc: $0.doc, task: $0.task) } }
                        .padding(.horizontal, 18).padding(.bottom, 18).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(t.canvas)
    }

    var emptyText: String {
        switch bucket {
        case .inbox: return "Tasks without a date appear here. Type [] and a space in any document to add one."
        case .today: return "Nothing due today. Tasks in today's daily note, or with @today, appear here."
        case .upcoming: return "Tasks with a future date (type @ in a task to pick one) appear here."
        case .overdue: return "Nothing overdue."
        case .completed: return "Completed tasks appear here."
        }
    }
}

struct CalendarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    @ObservedObject var events = CalendarEvents.shared
    let focus: String?
    @State private var before = 7
    @State private var after = 30

    var body: some View {
        let _ = model.indexTick
        let today = model.todayKey
        let days = (-before...after).map { Day.add(today, days: $0) }
        VStack(spacing: 0) {
            PlannerHeader(title: "Calendar", symbol: "calendar") {
                DraftSegmented("Show", selection: model.settingBinding(\.calendarFilter), options: [("all", "All"), ("tasks", "Tasks"), ("notes", "Notes")])
                DraftToggleChip(title: "Completed", isOn: model.settingBinding(\.calendarShowCompleted))
                PillGroup { PillButton(symbol: "sun.max", label: "Today (⇧⌘D)", text: "Today") { model.openDaily() } }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Button("Show earlier days") { before += 14 }.buttonStyle(.link).padding(.leading, 4)
                        ForEach(days, id: \.self) { d in DayCard(day: d, filter: model.settings.calendarFilter, showCompleted: model.settings.calendarShowCompleted).id(d) }
                        Button("Show later days") { after += 30 }.buttonStyle(.link).padding(.leading, 4)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    if let f = focus, !days.contains(f) { let n = Day.distance(from: today, to: f); if n < 0 { before = -n } else { after = n + 7 } }
                    DispatchQueue.main.async { proxy.scrollTo(focus ?? today, anchor: .top) }
                }
            }
        }
        .background(t.canvas)
    }
}

struct DayCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    @ObservedObject var events = CalendarEvents.shared
    let day: String
    let filter: String
    let showCompleted: Bool
    @State private var newTask = ""

    var body: some View {
        let today = model.todayKey
        let note = model.library.liveDocs.first { $0.dailyDate == day }
        let tasks = model.tasks(on: day).filter { showCompleted || !$0.task.checked }
        let evs = model.settings.calendarEvents ? events.events(on: day) : []
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Day.title(day)).font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(day == today ? t.accent : t.text).accessibilityAddTraits(.isHeader)
                if day == today { Text("Today").font(.system(size: DS.caption, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(t.accent.opacity(0.15))).foregroundStyle(t.accent) }
                Spacer()
            }
            if filter != "tasks" {
                if let note {
                    Button { model.openView(.doc(note.id)) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text").foregroundStyle(t.accent)
                            Text(note.excerpt.isEmpty ? "Daily note" : note.excerpt).lineLimit(2).foregroundStyle(t.text)
                            Spacer()
                        }.font(.system(size: DS.body)).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Open daily note for \(Day.title(day))")
                } else {
                    Button { model.openDaily(day) } label: { Label("Create Daily Note", systemImage: "plus.circle") }
                        .buttonStyle(.plain).font(.system(size: DS.body)).foregroundStyle(t.secondary)
                }
                ForEach(evs, id: \.eventIdentifier) { e in
                    HStack(spacing: 8) {
                        Circle().fill(Color(nsColor: e.calendar.color)).frame(width: 7, height: 7)
                        Text(e.isAllDay ? "All day" : e.startDate.formatted(date: .omitted, time: .shortened)).foregroundStyle(t.secondary).frame(width: 64, alignment: .leading)
                        Text(e.title ?? "Event").foregroundStyle(t.text).lineLimit(1)
                    }.font(.system(size: DS.body)).accessibilityElement(children: .combine)
                }
            }
            if filter != "notes" {
                ForEach(tasks, id: \.task.block) { TaskRow(doc: $0.doc, task: $0.task, showDue: false) }
                HStack(spacing: 8) {
                    Image(systemName: "plus").foregroundStyle(t.tertiary).accessibilityHidden(true)
                    TextField("Add Task", text: $newTask).textFieldStyle(.plain).font(.system(size: DS.body))
                        .onSubmit { model.addTask(newTask, on: day); newTask = "" }
                        .accessibilityLabel("Add a task for \(Day.title(day))")
                }.padding(.horizontal, 12).padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).fill(t.card.opacity(day == today ? 1 : 0.7)))
        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous).strokeBorder(day == today ? t.accent.opacity(0.4) : t.line, lineWidth: day == today ? 1 : 0.5))
    }
}

struct TagView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    let tag: String

    var body: some View {
        let _ = model.indexTick
        let hits = model.index.tagged(tag, live: model.liveIds)
        let byDoc = Dictionary(grouping: hits, by: \.doc).sorted { model.docTitle($0.key) < model.docTitle($1.key) }
        VStack(spacing: 0) {
            PlannerHeader(title: "#" + tag, symbol: "number", tint: Color(hex: model.tagColor(tag))) {
                HStack(spacing: 5) {
                    ForEach(Tags.palette, id: \.self) { hex in
                        Button { model.setTagColor(tag, hex) } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(t.text.opacity(model.tagColor(tag) == hex ? 0.7 : 0), lineWidth: 2))
                        }.buttonStyle(.plain).accessibilityLabel("Tag color \(hex)").accessibilityAddTraits(model.tagColor(tag) == hex ? .isSelected : [])
                    }
                }
            }
            if hits.isEmpty {
                EmptyLibrary(message: "No blocks use #\(tag) any more.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Text("\(hits.count) block\(hits.count == 1 ? "" : "s") in \(byDoc.count) document\(byDoc.count == 1 ? "" : "s")").font(.system(size: DS.body)).foregroundStyle(t.secondary)
                        ForEach(byDoc, id: \.key) { doc, items in
                            VStack(alignment: .leading, spacing: 4) {
                                Button(model.docTitle(doc)) { model.openView(.doc(doc)) }.buttonStyle(.plain).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text)
                                ForEach(Array(Set(items.map(\.tag.block))).sorted(), id: \.self) { b in
                                    let text = items.first { $0.tag.block == b }?.tag.text ?? ""
                                    Button { model.openBlock(doc, b) } label: {
                                        Text(text).font(.system(size: DS.body)).foregroundStyle(t.secondary).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(10).background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.card))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }.padding(.horizontal, 18).padding(.bottom, 24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(t.canvas)
    }
}

struct BacklinksPane: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    let docId: String
    var body: some View {
        let _ = model.indexTick
        let links = model.index.backlinks(to: docId, live: model.liveIds)
        let groups = Dictionary(grouping: links, by: \.source).sorted { model.docTitle($0.key) < model.docTitle($1.key) }
        PaneTitle(title: "Backlinks")
        if links.isEmpty { EmptyHint(text: "Documents that link here appear in this list. Type [[ in another document to link to this one.") }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(groups, id: \.key) { src, items in
                    VStack(alignment: .leading, spacing: 3) {
                        RailRow(icon: "doc.text", title: model.docTitle(src)) { model.openView(.doc(src), inPlace: true) }
                        let unique = items.reduce(into: [VaultIndex.Backlink]()) { acc, l in if !acc.contains(where: { $0.link.block == l.link.block }) { acc.append(l) } } // one row per mentioning block
                        ForEach(unique) { l in
                            Button { model.openDocLink(src, block: l.link.block) } label: {
                                Text(l.link.text).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.hover))
                            }
                            .buttonStyle(.plain).padding(.leading, 8)
                            .accessibilityLabel("Mention in \(model.docTitle(src)): \(l.link.text)")
                        }
                    }
                }
            }.padding(.horizontal, 6)
        }
    }
}

/// Due date and optional time for a task; writes a date chip into the source block.
struct DuePicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.undoManager) var undo
    @Environment(\.dismiss) var dismiss
    let doc: String
    let task: IndexedTask
    @State private var date = Date()
    @State private var withTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Due", selection: $date, displayedComponents: [.date]).datePickerStyle(.graphical).labelsHidden()
            Toggle("Time", isOn: $withTime)
            if withTime { DatePicker("Time", selection: $date, displayedComponents: [.hourAndMinute]).labelsHidden() }
            HStack {
                if task.due != nil { Button("Remove Date", role: .destructive) { model.setTaskDue(doc, task.block, due: nil, undo: undo); dismiss() } }
                Spacer()
                Button("Set") {
                    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = withTime ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
                    model.setTaskDue(doc, task.block, due: f.string(from: date), undo: undo); dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(14).frame(width: 260)
        .onAppear {
            if let d = task.due {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = d.count > 10 ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
                if let v = f.date(from: d) { date = v }
                withTime = d.count > 10
            } else if let v = Day.date(model.todayKey) { date = v }
        }
    }
}
