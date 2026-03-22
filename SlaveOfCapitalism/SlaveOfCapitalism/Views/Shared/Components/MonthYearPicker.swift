import SwiftUI

struct MonthYearPicker: View {
    @Binding var year: Int
    @Binding var month: Int

    var body: some View {
        HStack(spacing: 8) {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Text(Formatters.monthYear(year: year, month: month))
                .font(.headline)
                .frame(minWidth: 140)

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
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
}

#Preview {
    MonthYearPicker(year: .constant(2026), month: .constant(3))
}
