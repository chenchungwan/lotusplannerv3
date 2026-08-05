import SwiftUI

private struct WeeklyGridCell: Identifiable, Hashable {
    let row: Int
    let col: Int
    var id: String { "\(row)_\(col)" }
}

private struct WeeklyGridPos: Hashable {
    let row: Int
    let col: Int
}

private struct WeeklyGridPlacement: Hashable {
    var component: WeeklyCustomComponent
    var rowSpan: Int
    var colSpan: Int
}

struct WeeklyViewCustomConfigurator: View {
    @Environment(\.dismiss) private var dismiss

    private let versionId: UUID

    @State private var versionName = ""
    @State private var orientation: CustomWeeklyLayoutOrientation = .daysInColumns
    @State private var rows = 3
    @State private var cols = 7
    @State private var placements: [WeeklyGridPos: WeeklyGridPlacement] = [:]
    @State private var selectedPos: WeeklyGridPos?
    @State private var dropError: String?
    @State private var showingResetConfirmation = false

    @ObservedObject private var appPrefs = AppPreferences.shared

    private let minRowsOrCols = 1
    private let maxRowsOrCols = 12
    private let dayCount = 7

    init(versionId: UUID) {
        self.versionId = versionId
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    workArea
                        .frame(width: proxy.size.width * 2.0 / 3.0)

                    Divider()

                    componentPalette
                        .frame(width: proxy.size.width / 3.0)
                }
            }
            .navigationTitle("Customize Weekly View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    TextField("Version name", text: $versionName)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180, maxWidth: 260)
                        .submitLabel(.done)
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }

                    Button("Save") {
                        saveConfiguration()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert(
                "Can't Place Component",
                isPresented: Binding(
                    get: { dropError != nil },
                    set: { if !$0 { dropError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { dropError = nil }
            } message: {
                Text(dropError ?? "")
            }
            .alert("Start Fresh?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) { resetConfiguration() }
            } message: {
                Text("This clears your current weekly layout. You can still cancel without saving to keep the previously saved version.")
            }
            .onAppear {
                loadSavedConfiguration()
            }
        }
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 1000, minHeight: 680)
        #endif
    }

    private var workArea: some View {
        VStack(spacing: 0) {
            editHeader

            GeometryReader { proxy in
                let padding: CGFloat = 16
                let available = CGSize(width: max(0, proxy.size.width - padding * 2), height: max(0, proxy.size.height - padding * 2))

                VStack(spacing: 8) {
                    Text("Weekly Page")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    weeklyGrid(size: available)
                        .frame(width: available.width, height: max(0, available.height - 60))
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
                }
                .padding(padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private var editHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Picker("Layout", selection: $orientation) {
                    ForEach(CustomWeeklyLayoutOrientation.allCases) { option in
                        Label(option.displayName, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .onChange(of: orientation) { _, newValue in
                    applyOrientationDefaults(newValue)
                }

                if orientation == .daysInColumns {
                    gridSizeControl(label: "Rows", value: rows, remove: removeRow, add: addRow)
                    Text("7 day columns")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("7 day rows")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    gridSizeControl(label: "Cols", value: cols, remove: removeColumn, add: addColumn)
                }

                Spacer()

                if !placements.isEmpty {
                    Button(role: .destructive) {
                        placements.removeAll()
                        selectedPos = nil
                    } label: {
                        Label("Clear Components", systemImage: "trash")
                    }
                }
            }

            selectedComponentControls
        }
        .padding()
    }

    @ViewBuilder
    private var selectedComponentControls: some View {
        if let pos = selectedPos, let placement = placements[pos] {
            HStack(spacing: 10) {
                Label(placement.component.displayName(
                    personal: appPrefs.personalAccountName,
                    professional: appPrefs.professionalAccountName
                ), systemImage: placement.component.systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

                Text("\(placement.colSpan)x\(placement.rowSpan)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Divider()
                    .frame(height: 20)

                Button {
                    expandHeight(pos)
                } label: {
                    Label("Merge Down", systemImage: "arrow.down.to.line")
                }
                .disabled(!canExpandHeight(pos: pos, placement: placement))

                Button {
                    shrinkHeight(pos)
                } label: {
                    Label("Unmerge Up", systemImage: "arrow.up.to.line")
                }
                .disabled(placement.rowSpan <= minimumRowSpan(for: placement.component))

                Button {
                    expandWidth(pos)
                } label: {
                    Label("Merge Right", systemImage: "arrow.right.to.line")
                }
                .disabled(!canExpandWidth(pos: pos, placement: placement))

                Button {
                    shrinkWidth(pos)
                } label: {
                    Label("Unmerge Left", systemImage: "arrow.left.to.line")
                }
                .disabled(placement.colSpan <= minimumColSpan(for: placement.component))

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    placements[pos] = nil
                    selectedPos = nil
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        } else {
            Text("Select a component to merge or unmerge cells.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func gridSizeControl(label: String, value: Int, remove: @escaping () -> Void, add: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .disabled(value <= minRowsOrCols)

            Text("\(value)")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 16)

            Button(action: add) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .disabled(value >= maxRowsOrCols)
        }
    }

    private func weeklyGrid(size: CGSize) -> some View {
        let spacing: CGFloat = 6
        let padding: CGFloat = 8
        let headerHeight: CGFloat = 44
        let rowHeaderWidth: CGFloat = 64

        switch orientation {
        case .daysInColumns:
            let innerW = max(0, size.width - padding * 2)
            let innerH = max(0, size.height - headerHeight - padding * 2)
            let cellW = max(0, (innerW - spacing * CGFloat(cols - 1)) / CGFloat(cols))
            let cellH = max(0, (innerH - spacing * CGFloat(rows - 1)) / CGFloat(rows))

            return AnyView(
                VStack(spacing: 0) {
                    weekColumnHeaderPreview(dayWidth: cellW, spacing: spacing)
                        .frame(width: innerW, height: headerHeight)
                        .padding(.horizontal, padding)

                    placementGrid(cellW: cellW, cellH: cellH, spacing: spacing, padding: padding)
                        .frame(width: innerW + padding * 2, height: innerH + padding * 2)
                }
            )
        case .daysInRows:
            let innerW = max(0, size.width - padding * 2 - rowHeaderWidth)
            let innerH = max(0, size.height - padding * 2)
            let cellW = max(0, (innerW - spacing * CGFloat(cols - 1)) / CGFloat(cols))
            let cellH = max(0, (innerH - spacing * CGFloat(rows - 1)) / CGFloat(rows))

            return AnyView(
                HStack(spacing: 0) {
                    weekRowHeaderPreview(rowHeight: cellH, spacing: spacing)
                        .frame(width: rowHeaderWidth, height: innerH)

                    placementGrid(cellW: cellW, cellH: cellH, spacing: spacing, padding: padding)
                        .frame(width: innerW + padding * 2, height: innerH + padding * 2)
                }
            )
        }
    }

    private func placementGrid(cellW: CGFloat, cellH: CGFloat, spacing: CGFloat, padding: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(cells) { cell in
                let x = CGFloat(cell.col) * (cellW + spacing) + padding
                let y = CGFloat(cell.row) * (cellH + spacing) + padding
                gridCell(row: cell.row, col: cell.col)
                    .frame(width: cellW, height: cellH)
                    .contentShape(Rectangle())
                    .dropDestination(for: WeeklyComponentDragPayload.self) { items, _ in
                        guard let payload = items.first else { return false }
                        applyDrop(payload, targetRow: cell.row, targetCol: cell.col)
                        return true
                    }
                    .position(x: x + cellW / 2, y: y + cellH / 2)
            }

            ForEach(sortedPlacements, id: \.0) { pos, placement in
                let width = cellW * CGFloat(placement.colSpan) + spacing * CGFloat(max(0, placement.colSpan - 1))
                let height = cellH * CGFloat(placement.rowSpan) + spacing * CGFloat(max(0, placement.rowSpan - 1))
                let x = CGFloat(pos.col) * (cellW + spacing) + padding
                let y = CGFloat(pos.row) * (cellH + spacing) + padding

                placementCard(placement, isSelected: selectedPos == pos)
                    .frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPos = pos
                    }
                    .modifier(
                        WeeklyCellDragModifier(
                            component: placement.component,
                            row: pos.row,
                            col: pos.col
                        )
                    )
                    .contextMenu {
                        spanControls(row: pos.row, col: pos.col)

                        Button(role: .destructive) {
                            placements[pos] = nil
                            if selectedPos == pos {
                                selectedPos = nil
                            }
                        } label: {
                            Label("Delete Component", systemImage: "trash")
                        }
                    }
                    .position(x: x + width / 2, y: y + height / 2)
            }
        }
    }

    private var sortedPlacements: [(WeeklyGridPos, WeeklyGridPlacement)] {
        placements.sorted { lhs, rhs in
            lhs.key.row == rhs.key.row ? lhs.key.col < rhs.key.col : lhs.key.row < rhs.key.row
        }
    }

    private func weekColumnHeaderPreview(dayWidth: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(weekdayLabels, id: \.self) { day in
                dayHeaderLabel(day)
                    .frame(width: dayWidth)
                    .overlay(
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
            }
        }
    }

    private func weekRowHeaderPreview(rowHeight: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(weekdayLabels, id: \.self) { day in
                dayHeaderLabel(day)
                    .frame(height: rowHeight)
                    .overlay(
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 0.5),
                        alignment: .bottom
                    )
            }
        }
    }

    private var weekdayLabels: [String] {
        ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    }

    private func dayHeaderLabel(_ day: String) -> some View {
        Text(day)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.08))
    }

    private var cells: [WeeklyGridCell] {
        (0..<rows).flatMap { row in
            (0..<cols).map { col in WeeklyGridCell(row: row, col: col) }
        }
    }

    private func gridCell(row: Int, col: Int) -> some View {
        let coveredBySpan = placementCovering(row: row, col: col) != nil

        return RoundedRectangle(cornerRadius: 8)
            .stroke(
                style: StrokeStyle(lineWidth: 1, dash: [6])
            )
            .foregroundColor(coveredBySpan ? .accentColor.opacity(0.35) : .secondary.opacity(0.5))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(coveredBySpan ? Color.accentColor.opacity(0.035) : Color(.secondarySystemBackground))
            )
            .overlay {
                if placementCovering(row: row, col: col) != nil {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                        .foregroundColor(.accentColor.opacity(0.45))
                } else {
                    Text(cellLabel(row: row, col: col))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
    }

    private func placementCard(_ placement: WeeklyGridPlacement, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5))
            .foregroundColor(isSelected ? .blue : .accentColor)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((isSelected ? Color.blue : Color.accentColor).opacity(0.08))
            )
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: placement.component.systemImage)
                        .foregroundColor(.accentColor)
                    Text(placement.component.displayName(
                        personal: appPrefs.personalAccountName,
                        professional: appPrefs.professionalAccountName
                    ))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
                    if placement.rowSpan > 1 || placement.colSpan > 1 {
                        Text("\(placement.colSpan)x\(placement.rowSpan)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
    }

    private var availablePaletteComponents: [WeeklyCustomComponent] {
        var items: [WeeklyCustomComponent] = [
            .pastWeekSummary,
            .eventsWeek,
            .eventsWeeklyList,
            .personalTasksWeek,
            .personalTasksWeeklyList,
            .professionalTasksWeek,
            .professionalTasksWeeklyList
        ]
        if appPrefs.showWeightLogs {
            items.append(.weightLogWeek)
            items.append(.weightGraphWeek)
        }
        if appPrefs.showWorkoutLogs {
            items.append(.workoutLogWeek)
            items.append(.workoutStreakGraphWeek)
        }
        if appPrefs.showFoodLogs { items.append(.foodLogWeek) }
        if appPrefs.showWaterLogs { items.append(.waterLogWeek) }
        if appPrefs.showSleepLogs { items.append(.sleepLogWeek) }
        if appPrefs.showCustomLogs(for: 0) {
            items.append(.customLogDailyWeek)
            items.append(.customLogWeek)
        }
        if appPrefs.showCustomLogs(for: 1) {
            items.append(.customLogDailyWeek2)
            items.append(.customLogWeek2)
        }
        if !appPrefs.hideGoals {
            items.append(.weeklyGoals)
            items.append(.monthlyGoals)
            items.append(.yearlyGoals)
            items.append(.goalsPicker)
            items.append(.weeklyGoalsBar)
        }
        if appPrefs.showWeightLogs {
            items.append(.weightGraph)
            items.append(.weightGraphMonth)
            items.append(.weightGraphYear)
        }
        if appPrefs.showWorkoutLogs {
            items.append(.workoutStreakGraph)
            items.append(.workoutStreakGraphMonth)
            items.append(.workoutStreakGraphYear)
        }

        let placed = Set(placements.values.map(\.component))
        return items.filter { !placed.contains($0) }
    }

    private var componentPalette: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Components")
                    .font(.headline)
                Text("Drag a component into the weekly grid.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 8) {
                    ForEach(availablePaletteComponents) { component in
                        componentCard(component)
                            .draggable(
                                WeeklyComponentDragPayload(
                                    component: component,
                                    sourceRow: nil,
                                    sourceCol: nil
                                )
                            ) {
                                componentCard(component)
                                    .frame(width: 220)
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemBackground))
    }

    private func componentCard(_ component: WeeklyCustomComponent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: component.systemImage)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            Text(component.displayName(
                personal: appPrefs.personalAccountName,
                professional: appPrefs.professionalAccountName
            ))
            .font(.body)
            .foregroundColor(.primary)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func applyDrop(_ payload: WeeklyComponentDragPayload, targetRow: Int, targetCol: Int) {
        let normalized = normalizedPlacement(
            component: payload.component,
            targetRow: targetRow,
            targetCol: targetCol,
            rowSpan: 1,
            colSpan: 1
        )
        let target = normalized.pos

        if !payload.isFromPalette,
           payload.sourceRow == target.row,
           payload.sourceCol == target.col {
            return
        }

        if payload.isFromPalette && placements.values.map(\.component).contains(payload.component) {
            dropError = "That component is already on the grid. Drag the existing card to move it."
            return
        }

        var proposed = placements
        var placementToApply = normalized.placement
        if let sourceRow = payload.sourceRow, let sourceCol = payload.sourceCol {
            let sourcePos = WeeklyGridPos(row: sourceRow, col: sourceCol)
            if let existing = proposed[sourcePos] {
                placementToApply = normalizedPlacement(
                    component: payload.component,
                    targetRow: targetRow,
                    targetCol: targetCol,
                    rowSpan: existing.rowSpan,
                    colSpan: existing.colSpan
                ).placement
            }
            proposed[sourcePos] = nil
        }
        guard canPlace(placementToApply, at: target, in: proposed) else {
            dropError = "\(payload.component.displayName(personal: appPrefs.personalAccountName, professional: appPrefs.professionalAccountName)) needs open cells in its required weekly span."
            return
        }
        proposed[target] = placementToApply
        placements = proposed
        selectedPos = target
    }

    private func addRow() {
        guard orientation == .daysInColumns else { return }
        guard rows < maxRowsOrCols else { return }
        rows += 1
    }

    private func removeRow() {
        guard orientation == .daysInColumns else { return }
        guard rows > minRowsOrCols else { return }
        let newRows = rows - 1
        placements = placements
            .filter { $0.key.row < newRows }
            .mapValues { placement in
                var trimmed = placement
                trimmed.rowSpan = min(trimmed.rowSpan, max(1, newRows))
                return trimmed
            }
        rows = newRows
        if let selectedPos, selectedPos.row >= rows {
            self.selectedPos = nil
        }
    }

    private func addColumn() {
        guard orientation == .daysInRows else { return }
        guard cols < maxRowsOrCols else { return }
        cols += 1
    }

    private func removeColumn() {
        guard orientation == .daysInRows else { return }
        guard cols > minRowsOrCols else { return }
        let newCols = cols - 1
        placements = placements
            .filter { $0.key.col < newCols }
            .mapValues { placement in
                var trimmed = placement
                trimmed.colSpan = min(trimmed.colSpan, max(1, newCols))
                return trimmed
            }
        cols = newCols
        if let selectedPos, selectedPos.col >= cols {
            self.selectedPos = nil
        }
    }

    private func loadSavedConfiguration() {
        let library = CustomWeeklyViewLibrary.load()
        guard let version = library.versions.first(where: { $0.id == versionId }) else {
            versionName = "My Custom Week"
            return
        }
        versionName = version.name
        orientation = version.config.orientation
        rows = max(minRowsOrCols, min(maxRowsOrCols, orientation.fixedRows ?? version.config.rows))
        cols = max(minRowsOrCols, min(maxRowsOrCols, orientation.fixedCols ?? version.config.cols))

        var loaded: [WeeklyGridPos: WeeklyGridPlacement] = [:]
        for dto in version.config.placements {
            if let component = WeeklyCustomComponent(rawValue: dto.component) {
                let normalized = normalizedPlacement(
                    component: component,
                    targetRow: dto.row,
                    targetCol: dto.col,
                    rowSpan: dto.rowSpan,
                    colSpan: dto.colSpan
                )
                if canPlace(normalized.placement, at: normalized.pos, in: loaded) {
                    loaded[normalized.pos] = normalized.placement
                }
            }
        }
        placements = loaded
        selectedPos = nil
    }

    private func saveConfiguration() {
        let trimmedName = versionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "My Custom Week" : trimmedName
        let config = CustomWeeklyViewConfig(
            orientation: orientation,
            rows: rows,
            cols: cols,
            placements: placements
                .sorted { lhs, rhs in
                    lhs.key.row == rhs.key.row ? lhs.key.col < rhs.key.col : lhs.key.row < rhs.key.row
                }
                .map { pos, placement in
                    CustomWeeklyViewConfig.PlacementDTO(
                        row: pos.row,
                        col: pos.col,
                        rowSpan: placement.rowSpan,
                        colSpan: placement.colSpan,
                        component: placement.component.rawValue
                    )
                }
        )

        var library = CustomWeeklyViewLibrary.load()
        if let idx = library.versions.firstIndex(where: { $0.id == versionId }) {
            library.versions[idx].name = finalName
            library.versions[idx].config = config
        } else {
            guard library.versions.count < CustomWeeklyViewLibrary.maxVersions else { return }
            library.versions.append(
                NamedCustomWeeklyViewConfig(id: versionId, name: finalName, config: config)
            )
        }
        if library.activeId == nil {
            library.activeId = versionId
        }
        CustomWeeklyViewLibrary.localActiveId = versionId
        CustomWeeklyViewLibrary.save(library)
    }

    private func resetConfiguration() {
        applyOrientationDefaults(orientation)
        placements.removeAll()
        selectedPos = nil
    }

    private func applyOrientationDefaults(_ newOrientation: CustomWeeklyLayoutOrientation) {
        placements.removeAll()
        selectedPos = nil
        switch newOrientation {
        case .daysInColumns:
            rows = 3
            cols = dayCount
        case .daysInRows:
            rows = dayCount
            cols = 3
        }
    }

    private func normalizedPlacement(
        component: WeeklyCustomComponent,
        targetRow: Int,
        targetCol: Int,
        rowSpan: Int,
        colSpan: Int
    ) -> (pos: WeeklyGridPos, placement: WeeklyGridPlacement) {
        if component.isDayByDay {
            switch orientation {
            case .daysInColumns:
                let safeRow = min(max(0, targetRow), rows - 1)
                return (
                    WeeklyGridPos(row: safeRow, col: 0),
                    WeeklyGridPlacement(component: component, rowSpan: max(1, min(rowSpan, rows - safeRow)), colSpan: dayCount)
                )
            case .daysInRows:
                let safeCol = min(max(0, targetCol), cols - 1)
                return (
                    WeeklyGridPos(row: 0, col: safeCol),
                    WeeklyGridPlacement(component: component, rowSpan: dayCount, colSpan: max(1, min(colSpan, cols - safeCol)))
                )
            }
        }

        let safeRow = min(max(0, targetRow), rows - 1)
        let safeCol = min(max(0, targetCol), cols - 1)
        return (
            WeeklyGridPos(row: safeRow, col: safeCol),
            WeeklyGridPlacement(
                component: component,
                rowSpan: max(1, min(rowSpan, rows - safeRow)),
                colSpan: max(1, min(colSpan, cols - safeCol))
            )
        )
    }

    private func canPlace(
        _ placement: WeeklyGridPlacement,
        at pos: WeeklyGridPos,
        in proposed: [WeeklyGridPos: WeeklyGridPlacement]
    ) -> Bool {
        guard pos.row >= 0,
              pos.col >= 0,
              pos.row + placement.rowSpan <= rows,
              pos.col + placement.colSpan <= cols else {
            return false
        }

        let claimed = cellsCovered(by: placement, at: pos)
        for (otherPos, otherPlacement) in proposed {
            let otherClaimed = cellsCovered(by: otherPlacement, at: otherPos)
            if !claimed.isDisjoint(with: otherClaimed) {
                return false
            }
        }
        return true
    }

    private func cellsCovered(by placement: WeeklyGridPlacement, at pos: WeeklyGridPos) -> Set<WeeklyGridPos> {
        Set((pos.row..<(pos.row + placement.rowSpan)).flatMap { row in
            (pos.col..<(pos.col + placement.colSpan)).map { col in
                WeeklyGridPos(row: row, col: col)
            }
        })
    }

    private func placementCovering(row: Int, col: Int) -> WeeklyGridPlacement? {
        let pos = WeeklyGridPos(row: row, col: col)
        return placements.first { origin, placement in
            origin != pos && cellsCovered(by: placement, at: origin).contains(pos)
        }?.value
    }

    private func cellLabel(row: Int, col: Int) -> String {
        switch orientation {
        case .daysInColumns:
            return "\(row + 1)"
        case .daysInRows:
            return weekdayLabels[row]
        }
    }

    @ViewBuilder
    private func spanControls(row: Int, col: Int) -> some View {
        let pos = WeeklyGridPos(row: row, col: col)
        if let placement = placements[pos] {
            if canExpandHeight(pos: pos, placement: placement) {
                Button {
                    expandHeight(pos)
                } label: {
                    Label("Merge Row Below", systemImage: "arrow.down.to.line")
                }
            }
            if placement.rowSpan > minimumRowSpan(for: placement.component) {
                Button {
                    shrinkHeight(pos)
                } label: {
                    Label("Unmerge Bottom Row", systemImage: "arrow.up.to.line")
                }
            }
            if canExpandWidth(pos: pos, placement: placement) {
                Button {
                    expandWidth(pos)
                } label: {
                    Label("Merge Column Right", systemImage: "arrow.right.to.line")
                }
            }
            if placement.colSpan > minimumColSpan(for: placement.component) {
                Button {
                    shrinkWidth(pos)
                } label: {
                    Label("Unmerge Right Column", systemImage: "arrow.left.to.line")
                }
            }
        }
    }

    private func minimumRowSpan(for component: WeeklyCustomComponent) -> Int {
        component.isDayByDay && orientation == .daysInRows ? dayCount : 1
    }

    private func minimumColSpan(for component: WeeklyCustomComponent) -> Int {
        component.isDayByDay && orientation == .daysInColumns ? dayCount : 1
    }

    private func canExpandHeight(pos: WeeklyGridPos, placement: WeeklyGridPlacement) -> Bool {
        guard pos.row + placement.rowSpan < rows else { return false }
        if placement.component.isDayByDay && orientation == .daysInRows { return false }
        var expanded = placement
        expanded.rowSpan += 1
        var proposed = placements
        proposed[pos] = nil
        return canPlace(expanded, at: pos, in: proposed)
    }

    private func canExpandWidth(pos: WeeklyGridPos, placement: WeeklyGridPlacement) -> Bool {
        guard pos.col + placement.colSpan < cols else { return false }
        if placement.component.isDayByDay && orientation == .daysInColumns { return false }
        var expanded = placement
        expanded.colSpan += 1
        var proposed = placements
        proposed[pos] = nil
        return canPlace(expanded, at: pos, in: proposed)
    }

    private func expandHeight(_ pos: WeeklyGridPos) {
        guard var placement = placements[pos], canExpandHeight(pos: pos, placement: placement) else { return }
        placement.rowSpan += 1
        placements[pos] = placement
        selectedPos = pos
    }

    private func shrinkHeight(_ pos: WeeklyGridPos) {
        guard var placement = placements[pos],
              placement.rowSpan > minimumRowSpan(for: placement.component) else { return }
        placement.rowSpan -= 1
        placements[pos] = placement
        selectedPos = pos
    }

    private func expandWidth(_ pos: WeeklyGridPos) {
        guard var placement = placements[pos], canExpandWidth(pos: pos, placement: placement) else { return }
        placement.colSpan += 1
        placements[pos] = placement
        selectedPos = pos
    }

    private func shrinkWidth(_ pos: WeeklyGridPos) {
        guard var placement = placements[pos],
              placement.colSpan > minimumColSpan(for: placement.component) else { return }
        placement.colSpan -= 1
        placements[pos] = placement
        selectedPos = pos
    }
}

private struct WeeklyCellDragModifier: ViewModifier {
    let component: WeeklyCustomComponent?
    let row: Int
    let col: Int

    func body(content: Content) -> some View {
        if let component {
            content.draggable(
                WeeklyComponentDragPayload(
                    component: component,
                    sourceRow: row,
                    sourceCol: col
                )
            ) {
                Label(component.displayName(
                    personal: AppPreferences.shared.personalAccountName,
                    professional: AppPreferences.shared.professionalAccountName
                ), systemImage: component.systemImage)
                .padding(10)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } else {
            content
        }
    }
}

#Preview {
    WeeklyViewCustomConfigurator(versionId: UUID())
}
