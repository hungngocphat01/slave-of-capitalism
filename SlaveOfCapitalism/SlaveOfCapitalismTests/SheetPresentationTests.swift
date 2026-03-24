import XCTest
@testable import SlaveOfCapitalism

final class SheetPresentationTests: XCTestCase {
    func testSplitPaymentAmountPresentationUsesUserShareAsPrimaryAndTotalAsSecondary() {
        let transaction = makeTransaction(
            amount: Decimal(string: "120")!,
            classification: .splitPayment,
            linkedEntry: LinkedEntryResponse(
                id: 10,
                linkType: .splitPayment,
                primaryTransactionId: 1,
                counterpartyName: "Alex",
                totalAmount: Decimal(string: "120")!,
                userAmount: Decimal(string: "45")!,
                pendingAmount: Decimal(string: "75")!,
                status: .pending,
                notes: nil,
                createdAt: "2026-03-23T00:00:00Z",
                updatedAt: "2026-03-23T00:00:00Z",
                linkedTransactions: []
            )
        )

        let presentation = TransactionAmountPresentation.make(for: transaction)

        XCTAssertEqual(presentation.primaryText, Formatters.currency(Decimal(string: "45")!))
        XCTAssertEqual(presentation.secondaryText, "(over \(Formatters.currency(Decimal(string: "120")!)))")
    }

    func testRegularExpenseAmountPresentationHasNoSecondaryLineOrMinusSign() {
        let transaction = makeTransaction(amount: Decimal(string: "88")!)

        let presentation = TransactionAmountPresentation.make(for: transaction)

        XCTAssertEqual(presentation.primaryText, Formatters.currency(Decimal(string: "88")!))
        XCTAssertNil(presentation.secondaryText)
    }

    func testRegularIncomeAmountPresentationKeepsPlusSign() {
        let transaction = makeTransaction(
            amount: Decimal(string: "88")!,
            classification: .income,
            direction: .inflow
        )

        let presentation = TransactionAmountPresentation.make(for: transaction)

        XCTAssertEqual(presentation.primaryText, "+\(Formatters.currency(Decimal(string: "88")!))")
        XCTAssertNil(presentation.secondaryText)
    }

    func testIgnoredOutflowAmountUsesMutedTintRole() {
        let transaction = makeTransaction(
            amount: Decimal(string: "88")!,
            isIgnored: true
        )

        XCTAssertEqual(TransactionAmountPresentation.tintRole(for: transaction), .muted)
    }

    func testIgnoredInflowAmountUsesMutedTintRole() {
        let transaction = makeTransaction(
            amount: Decimal(string: "88")!,
            classification: .income,
            direction: .inflow,
            isIgnored: true
        )

        XCTAssertEqual(TransactionAmountPresentation.tintRole(for: transaction), .muted)
    }

    func testTransactionBadgePresentationUsesSingleSplitPaymentTag() {
        let transaction = makeTransaction(
            amount: Decimal(string: "120")!,
            classification: .splitPayment,
            linkedEntry: LinkedEntryResponse(
                id: 10,
                linkType: .splitPayment,
                primaryTransactionId: 1,
                counterpartyName: "Alex",
                totalAmount: Decimal(string: "120")!,
                userAmount: Decimal(string: "45")!,
                pendingAmount: Decimal(string: "75")!,
                status: .pending,
                notes: nil,
                createdAt: "2026-03-23T00:00:00Z",
                updatedAt: "2026-03-23T00:00:00Z",
                linkedTransactions: []
            )
        )

        XCTAssertEqual(TransactionBadgePresentation.titles(for: transaction), ["Split Payment"])
    }

    func testTransactionBadgePresentationIncludesSpecialClassificationTags() {
        let transaction = makeTransaction(
            amount: Decimal(string: "1000")!,
            classification: .debtCollection,
            direction: .inflow
        )

        XCTAssertEqual(TransactionBadgePresentation.titles(for: transaction), ["Debt Collection"])
    }

    func testTransactionBadgePresentationShowsDoneForSettledSplitPayment() {
        let transaction = makeTransaction(
            amount: Decimal(string: "120")!,
            classification: .splitPayment,
            linkedEntry: LinkedEntryResponse(
                id: 10,
                linkType: .splitPayment,
                primaryTransactionId: 1,
                counterpartyName: "Alex",
                totalAmount: Decimal(string: "120")!,
                userAmount: Decimal(string: "45")!,
                pendingAmount: .zero,
                status: .settled,
                notes: nil,
                createdAt: "2026-03-23T00:00:00Z",
                updatedAt: "2026-03-23T00:00:00Z",
                linkedTransactions: []
            )
        )

        XCTAssertEqual(TransactionBadgePresentation.titles(for: transaction), ["Split Payment", "Done"])
    }

    func testLinkedEntryPresentationUsesSplitEntryBadgeForOwningTransaction() {
        let transaction = makeTransaction(
            amount: Decimal(string: "120")!,
            classification: .splitPayment,
            linkedEntry: LinkedEntryResponse(
                id: 10,
                linkType: .splitPayment,
                primaryTransactionId: 1,
                counterpartyName: "Alex",
                totalAmount: Decimal(string: "120")!,
                userAmount: Decimal(string: "45")!,
                pendingAmount: Decimal(string: "75")!,
                status: .pending,
                notes: nil,
                createdAt: "2026-03-23T00:00:00Z",
                updatedAt: "2026-03-23T00:00:00Z",
                linkedTransactions: []
            )
        )

        XCTAssertEqual(LinkedEntryPresentation.ownerBadgeText(for: transaction), "Split Entry")
    }

    func testLinkedEntryPresentationUsesRepaymentLanguageForSplitPaymentActions() {
        XCTAssertEqual(LinkedEntryPresentation.linkActionTitle(for: .splitPayment), "Link Repayment")
        XCTAssertEqual(LinkedEntryPresentation.linkSheetTitle(for: .splitPayment), "Link Repayment")
    }

    func testMarkAsSplitPreviewUsesCounterpartyNameAndRemainingAmount() {
        let preview = MarkAsSplitSheetPresentation.preview(
            totalAmount: Decimal(string: "120.50")!,
            userAmountText: "20.50",
            counterpartyName: "Alex"
        )

        XCTAssertEqual(preview?.counterpartyLabel, "Alex's Share")
        XCTAssertEqual(preview?.counterpartyAmount, Decimal(string: "100.00"))
    }

    func testMarkAsSplitPreviewFallsBackToGenericCounterpartyLabel() {
        let preview = MarkAsSplitSheetPresentation.preview(
            totalAmount: Decimal(string: "120")!,
            userAmountText: "50",
            counterpartyName: "  "
        )

        XCTAssertEqual(preview?.counterpartyLabel, "Counterparty Share")
        XCTAssertEqual(preview?.counterpartyAmount, Decimal(string: "70"))
    }

    func testMarkAsSplitPreviewRejectsInvalidAmounts() {
        XCTAssertNil(
            MarkAsSplitSheetPresentation.preview(
                totalAmount: Decimal(string: "120")!,
                userAmountText: "abc",
                counterpartyName: "Alex"
            )
        )
    }

    func testReclassifyOptionsMatchOutflowDirection() {
        XCTAssertEqual(
            ReclassifySheetPresentation.options(for: .outflow).map(\.classification),
            [.expense, .transfer, .loanRepayment, .installmtChrge]
        )
    }

    func testReclassifyOptionsIncludeUtilityDescriptions() {
        let option = ReclassifySheetPresentation.options(for: .inflow)
            .first(where: { $0.classification == .borrow })

        XCTAssertEqual(option?.title, "Borrow")
        XCTAssertEqual(option?.detail, "Track money you received as borrowed funds.")
    }

    func testAddTransactionCategoryPickerShowsEmojiAndNameTogether() {
        let category = CategoryWithSubcategories(
            id: 1,
            name: "Coffee",
            emoji: "☕",
            color: nil,
            isSystem: false,
            createdAt: "2026-03-23T00:00:00Z",
            updatedAt: "2026-03-23T00:00:00Z",
            subcategories: []
        )

        let sections = TransactionCategoryMenuModel.sections(from: [category])

        XCTAssertEqual(sections.first?.rows.first?.title, "☕ Coffee")
    }

    func testTransactionDetailSheetPresentationLocksStructureEditingForPrimaryLinkedEntries() {
        let transaction = makeTransaction(
            amount: Decimal(string: "120")!,
            classification: .splitPayment,
            linkedEntry: LinkedEntryResponse(
                id: 10,
                linkType: .splitPayment,
                primaryTransactionId: 1,
                counterpartyName: "Alex",
                totalAmount: Decimal(string: "120")!,
                userAmount: Decimal(string: "45")!,
                pendingAmount: Decimal(string: "75")!,
                status: .pending,
                notes: nil,
                createdAt: "2026-03-23T00:00:00Z",
                updatedAt: "2026-03-23T00:00:00Z",
                linkedTransactions: []
            )
        )

        XCTAssertTrue(TransactionDetailSheetPresentation.locksStructureEditing(for: transaction))
    }

    func testTransactionDetailSheetPresentationLocksStructureEditingForRepaymentTransactions() {
        let transaction = makeTransaction(
            amount: Decimal(string: "88")!,
            classification: .income,
            direction: .inflow,
            isLinkedToEntry: true
        )

        XCTAssertTrue(TransactionDetailSheetPresentation.locksStructureEditing(for: transaction))
    }

    func testTransactionDetailSheetPresentationShowsValidationBannerMessage() {
        XCTAssertEqual(
            TransactionDetailSheetPresentation.bannerMessage(
                validationMessage: "Description is required.",
                errorMessage: nil,
                isEditing: true
            ),
            "Description is required."
        )
    }

    private func makeTransaction(
        amount: Decimal,
        classification: TransactionClassification = .expense,
        direction: TransactionDirection = .outflow,
        isIgnored: Bool = false,
        isLinkedToEntry: Bool = false,
        linkedEntry: LinkedEntryResponse? = nil
    ) -> TransactionWithDetails {
        TransactionWithDetails(
            id: 1,
            date: "2026-03-23",
            time: nil,
            walletId: 1,
            direction: direction,
            amount: amount,
            classification: classification,
            description: "Dinner",
            categoryId: nil,
            subcategoryId: nil,
            pairedTransactionId: nil,
            isIgnored: isIgnored,
            isCalibration: false,
            createdAt: "2026-03-23T00:00:00Z",
            updatedAt: "2026-03-23T00:00:00Z",
            walletName: "Cash",
            walletType: WalletType.normal.rawValue,
            categoryName: nil,
            subcategoryName: nil,
            hasLinkedEntry: linkedEntry != nil,
            isLinkedToEntry: isLinkedToEntry,
            linkedEntry: linkedEntry
        )
    }
}
