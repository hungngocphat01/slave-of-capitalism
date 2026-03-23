import SwiftUI

struct MonthYearPicker: View {
    @Binding var year: Int
    @Binding var month: Int

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Text(Formatters.monthYear(year: year, month: month))
                .font(.largeTitle.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 16)

            ControlGroup {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                }

                Button(action: setToCurrentMonth) {
                    Text("Today")
                }

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                }
            }
            .controlSize(.regular)
        }
    }

    private func previousMonth() {
        if month == 1 {
            month = 12
            year -= 1
        } else {
            month -= 1
        }
    }

    private func nextMonth() {
        if month == 12 {
            month = 1
            year += 1
        } else {
            month += 1
        }
    }

    private func setToCurrentMonth() {
        let current = Calendar.current.dateComponents([.year, .month], from: .now)
        guard let currentYear = current.year, let currentMonth = current.month else { return }
        year = currentYear
        month = currentMonth
    }
}

#Preview {
    MonthYearPicker(year: .constant(2026), month: .constant(3))
}
