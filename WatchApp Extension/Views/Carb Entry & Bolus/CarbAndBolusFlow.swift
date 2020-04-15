//
//  CarbAndBolusFlow.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/23/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import HealthKit
import LoopKit


struct CarbAndBolusFlow: View {
    enum Configuration {
        case carbEntry
        case manualBolus
    }

    private enum FlowState {
        case carbEntry
        case bolusEntry
        case bolusConfirmation
    }

    // MARK: - State
    @State private var flowState: FlowState
    @ObservedObject private var viewModel: CarbAndBolusFlowViewModel
    @Environment(\.sizeClass) private var sizeClass

    // MARK: - State: Carb Entry
    @State private var carbAmount = 15
    @State private var carbEntryDate = Date()
    @State private var carbAbsorptionTime: CarbAbsorptionTime = .medium
    @State private var inputMode: CarbEntryInputMode = .carbs

    // MARK: - State: Bolus Entry
    @State private var bolusAmount: Double = 0
    @State private var receivedInitialBolusRecommendation = false
    @State private var showingRecommendationChangedAlert = false

    // MARK: - State: Bolus Confirmation
    @State private var bolusConfirmationProgress: Double = 0

    // MARK: - Initialization

    private var configuration: Configuration { viewModel.configuration }

    init(viewModel: CarbAndBolusFlowViewModel) {
        switch viewModel.configuration {
        case .carbEntry:
            _flowState = State(initialValue: .carbEntry)
        case .manualBolus:
            _flowState = State(initialValue: .bolusEntry)
        }

        self.viewModel = viewModel
    }

    // MARK: - View Tree

    var body: some View {
        VStack(spacing: 2) {
            inputViews
            Spacer()
            actionView
        }
        // Position the carb labels via preference keys propagated up from lower in the view tree.
        .overlayPreferenceValue(CarbAmountPositionKey.self, positionedCarbAmountLabel)
        .overlayPreferenceValue(GramLabelPositionKey.self, positionedGramLabel)

        // Handle incoming bolus recommendations.
        .onReceive(viewModel.$recommendedBolusAmount, perform: handleNewBolusRecommendation)
        .alert(isPresented: $showingRecommendationChangedAlert, content: recommendedBolusUpdatedAlert)

        // Handle error states.
        .alert(item: $viewModel.error, content: communicationErrorAlert(for:))
    }
}

// MARK: - Input views

extension CarbAndBolusFlow {
    private var inputViews: some View {
        VStack(spacing: 4) {
            if flowState == .carbEntry {
                CarbAndDateInput(
                    amount: $carbAmount,
                    date: $carbEntryDate,
                    initialDate: viewModel.interactionStartDate,
                    inputMode: $inputMode
                )
                .transition(.shrinkDownAndFade)
            } else {
                BolusInput(
                    amount: $bolusAmount,
                    isComputingRecommendedAmount: viewModel.isComputingRecommendedBolus,
                    recommendedAmount: viewModel.recommendedBolusAmount,
                    maxBolus: viewModel.maxBolus,
                    isEditable: flowState == .bolusEntry
                )
            }

            if configuration != .manualBolus && flowState != .bolusConfirmation {
                AbsorptionTimeSelection(
                    selectedAbsorptionTime: $carbAbsorptionTime,
                    expanded: absorptionButtonsExpanded,
                    amount: carbAmount
                )
            }
        }
        .padding(.top, topPaddingToPositionInputViews)
    }

    private var absorptionButtonsExpanded: Binding<Bool> {
        Binding(
            get: { self.flowState == .carbEntry },
            set: { isExpanded in isExpanded ? self.returnToCarbEntry() : self.transitionToBolusEntry() }
        )
    }

    private func returnToCarbEntry() {
        withAnimation {
            flowState = .carbEntry
        }
        receivedInitialBolusRecommendation = false
        viewModel.discardCarbEntryUnderConsideration()

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
            self.bolusAmount = 0
        }
    }

    private func transitionToBolusEntry() {
        viewModel.recommendBolus(forGrams: carbAmount, eatenAt: carbEntryDate, absorptionTime: carbAbsorptionTime)
        withAnimation {
            flowState = .bolusEntry
            inputMode = .carbs
        }
    }

    private var topPaddingToPositionInputViews: CGFloat {
        guard flowState == .bolusConfirmation else {
            return 0
        }

        // Derived via experimentation to hold the bolus amount label in place in transition to bolus confirmation.
        switch sizeClass {
        case .size38mm:
            return 2
        case .size42mm:
            return 0
        case .size40mm:
            return configuration == .carbEntry ? 7 : 19
        case .size44mm:
            return 5
        }
    }
}

// MARK: - Action views

extension CarbAndBolusFlow {
    private var actionView: some View {
        Group {
            if flowState == .carbEntry {
                continueToBolusEntryButton
            }

            if flowState == .bolusEntry {
                saveCarbsAndBolusButton
            }

            if flowState == .bolusConfirmation {
                bolusConfirmationView
            }
        }
    }

    private var continueToBolusEntryButton: some View {
        ActionButton(
            title: Text("Continue", comment: "Button text to continue from carb entry to bolus entry on Apple Watch"),
            color: .carbs
        ) {
            self.transitionToBolusEntry()
        }
        .offset(y: actionButtonOffsetY)
        .transition(.fadeIn(after: 0.175))
    }

    private var saveCarbsAndBolusButton: some View {
        ActionButton(
            title: saveButtonText,
            color: bolusAmount > 0 || configuration == .manualBolus ? .insulin : .blue
        ) {
            if self.bolusAmount > 0 {
                withAnimation {
                    self.flowState = .bolusConfirmation
                }
            } else if self.configuration == .carbEntry {
                self.viewModel.addCarbsWithoutBolusing()
            }
        }
        .offset(y: actionButtonOffsetY)
        .transition(.fadeIn(after: 0.35, removal: .identity))
    }

    private var saveButtonText: Text {
        switch configuration {
        case .carbEntry:
            return bolusAmount > 0
                ? Text("Save & Bolus", comment: "Button text to confirm carb entry and bolus on Apple Watch")
                : Text("Save", comment: "Button text to confirm carb entry without bolusing on Apple Watch")
        case .manualBolus:
            return Text("Bolus", comment: "Button text to confirm manual bolus on Apple Watch")
        }
    }

    private var actionButtonOffsetY: CGFloat {
        switch sizeClass {
        case .size38mm, .size42mm:
            return 0
        case .size40mm:
            return 20
        case .size44mm:
            return 27
        }
    }

    private var bolusConfirmationView: some View {
        BolusConfirmationView(progress: $bolusConfirmationProgress, onConfirmation: {
            self.viewModel.addCarbsAndDeliverBolus(self.bolusAmount)
        })
        .padding(.bottom, bolusConfirmationPadding)
        .transition(.fadeIn(after: 0.35))
    }

    private var bolusConfirmationPadding: CGFloat {
        switch sizeClass {
        case .size42mm:
            return 12
        default:
            return 0
        }
    }
}

// MARK: - Carb label layout

extension CarbAndBolusFlow {
    private var carbLabelScale: PositionedTextScale {
        flowState == .carbEntry ? .large : .small
    }

    private func positionedCarbAmountLabel(_ origin: Anchor<CGPoint>?) -> some View {
        origin.map { origin in
            carbLabelStyle(CarbAmountLabel(amount: carbAmount, origin: origin, scale: carbLabelScale))
        }
    }

    private func positionedGramLabel(_ origin: Anchor<CGPoint>?) -> some View {
        origin.map { origin in
            carbLabelStyle(GramLabel(origin: origin, scale: carbLabelScale))
        }
    }

    private func carbLabelStyle<Content: View>(_ content: Content) -> some View {
        let color: Color
        if flowState == .carbEntry {
            color = inputMode == .carbs ? .carbs : Color(.lightGray)
        } else {
            color = .white
        }

        return content
            .foregroundColor(color)
            .onTapGesture {
                if self.flowState == .carbEntry {
                    self.inputMode.toggle()
                } else {
                    self.returnToCarbEntry()
                }
            }
    }
}

// MARK: - Handling incoming data

extension CarbAndBolusFlow {
    private func handleNewBolusRecommendation(_ recommendedBolus: Double?) {
        guard flowState != .carbEntry else {
            return
        }

        if !receivedInitialBolusRecommendation {
            receivedInitialBolusRecommendation = true

            // If the user hasn't started to dial a bolus amount, update to the recommended amount.
            if flowState == .bolusEntry, bolusAmount == 0, let recommendedBolus = recommendedBolus {
                bolusAmount = recommendedBolus
            }
        } else {
            // Boot the user out of bolus confirmation to acknowledge the updated recommendation.
            if flowState == .bolusConfirmation {
                withAnimation {
                    flowState = .bolusEntry
                }
            }

            bolusAmount = recommendedBolus ?? 0
            showingRecommendationChangedAlert = true
        }
    }

    private func recommendedBolusUpdatedAlert() -> Alert {
        Alert(
            title: Text("Bolus Recommendation Updated", comment: "Alert title for updated bolus recommendation on Apple Watch"),
            message: Text("The bolus recommendation has updated. Please reconfirm the bolus amount.", comment: "Alert message for updated bolus recommendation on Apple Watch"),
            dismissButton: .default(Text("OK"))
        )
    }

    private func communicationErrorAlert(for error: CarbAndBolusFlowViewModel.Error) -> Alert {
        let dismissAction: () -> Void
        switch error {
        case .potentialCarbEntryMessageSendFailure:
            dismissAction = {}
        case .bolusMessageSendFailure:
            dismissAction = { self.bolusConfirmationProgress = 0 }
        }

        return Alert(
            title: Text(error.failureReason!),
            message: Text(error.recoverySuggestion!),
            dismissButton: .default(Text("OK"), action: dismissAction)
        )
    }
}