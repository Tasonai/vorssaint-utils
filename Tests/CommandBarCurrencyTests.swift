// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarCurrencyTests {
    static func run(_ suite: TestSuite) {
        let enUS = Locale(identifier: "en_US")
        let ruRU = Locale(identifier: "ru_RU")

        // 1. Basic conversions
        if let res = CommandBarCurrency.convert("100 usd in eur", decimalSeparator: ".", groupingSeparator: ",", locale: enUS) {
            suite.expectClose(res.value, 92.0, "100 USD to EUR evaluates near 92 EUR", tol: 1.0)
            suite.expect(res.sourceCode == "USD", "source code is USD")
            suite.expect(res.targetCode == "EUR", "target code is EUR")
            suite.expect(res.rateSummary.contains("USD") && res.rateSummary.contains("EUR"), "rate summary contains both codes")
        } else {
            suite.expect(false, "100 usd in eur failed to convert")
        }

        if let res = CommandBarCurrency.convert("100 eur to usd", decimalSeparator: ".", groupingSeparator: ",", locale: enUS) {
            suite.expectClose(res.value, 108.7, "100 EUR to USD evaluates near 108.7 USD", tol: 1.0)
            suite.expect(res.formatted.contains("$"), "formatted string has dollar symbol")
        } else {
            suite.expect(false, "100 eur to usd failed to convert")
        }

        // 2. Russian queries and currency symbols
        if let res = CommandBarCurrency.convert("1000 ₽ в usd", decimalSeparator: ",", groupingSeparator: " ", locale: ruRU) {
            suite.expectClose(res.value, 10.53, "1000 RUB to USD evaluates near 10.53 USD", tol: 0.5)
            suite.expect(res.sourceCode == "RUB", "ruble source code is RUB")
            suite.expect(res.targetCode == "USD", "target code is USD")
        } else {
            suite.expect(false, "1000 ₽ в usd failed to convert")
        }

        if let res = CommandBarCurrency.convert("100 usd в руб", decimalSeparator: ".", groupingSeparator: ",", locale: ruRU) {
            suite.expectClose(res.value, 9500.0, "100 USD to RUB evaluates near 9500 RUB", tol: 100.0)
            suite.expect(res.targetCode == "RUB", "target code is RUB")
        } else {
            suite.expect(false, "100 usd в руб failed to convert")
        }

        // 3. Prefix and suffix symbols ($100 to eur, 100$ in €)
        if let res = CommandBarCurrency.convert("$100 to eur", decimalSeparator: ".", groupingSeparator: ",", locale: enUS) {
            suite.expectClose(res.value, 92.0, "$100 to eur evaluates", tol: 1.0)
        } else {
            suite.expect(false, "$100 to eur failed to convert")
        }

        if let res = CommandBarCurrency.convert("100$ in €", decimalSeparator: ".", groupingSeparator: ",", locale: enUS) {
            suite.expectClose(res.value, 92.0, "100$ in € evaluates", tol: 1.0)
        } else {
            suite.expect(false, "100$ in € failed to convert")
        }

        // 4. Crypto and shorthand notation
        if let res = CommandBarCurrency.convert("2 btc in usd", decimalSeparator: ".", groupingSeparator: ",", locale: enUS) {
            suite.expect(res.value > 100_000, "2 BTC in USD is substantial value")
            suite.expect(res.sourceCode == "BTC", "BTC source recognized")
        } else {
            suite.expect(false, "2 btc in usd failed to convert")
        }

        if let res = CommandBarCurrency.convert("100 usd -> gbp", decimalSeparator: ".", groupingSeparator: ",", locale: enUS) {
            suite.expectClose(res.value, 79.0, "arrow notation works", tol: 1.0)
        } else {
            suite.expect(false, "100 usd -> gbp failed to convert")
        }

        // 5. Negative / invalid tests
        suite.expect(CommandBarCurrency.convert("100 usd in usd") == nil, "same currency returns nil")
        suite.expect(CommandBarCurrency.convert("100 km to mi") == nil, "distance is not a currency")
        suite.expect(CommandBarCurrency.convert("hello world") == nil, "plain text is not currency")
        suite.expect(CommandBarCurrency.convert("12345") == nil, "plain number is not currency")

        // 6. Fuzzy Math evaluation
        let mathRU = CommandBarMath.evaluate("20% от 500", decimalSeparator: ",", groupingSeparator: " ", locale: ruRU)
        suite.expect(mathRU?.value == 100.0, "Russian '20% от 500' evaluates to 100")

        let mathImplicit = CommandBarMath.evaluate("20% 500", decimalSeparator: ".", groupingSeparator: ",", locale: enUS)
        suite.expect(mathImplicit?.value == 100.0, "implicit product '20% 500' evaluates to 100")

        let mathCyrillicX = CommandBarMath.evaluate("5 х 10", decimalSeparator: ".", groupingSeparator: ",", locale: enUS)
        suite.expect(mathCyrillicX?.value == 50.0, "Cyrillic 'х' acts as multiplication sign")

        let mathPi = CommandBarMath.evaluate("2 * пи", decimalSeparator: ".", groupingSeparator: ",", locale: enUS)
        suite.expect(mathPi.map { abs($0.value - 6.28318) < 0.001 } == true, "Cyrillic 'пи' acts as pi constant")

        // 7. Russian unit conversions
        let unitKm = CommandBarUnits.convert("100 км в мили", decimalSeparator: ",", groupingSeparator: " ", locale: ruRU)
        suite.expect(unitKm.map { abs($0.value - 62.1371) < 0.01 } == true, "100 км в мили converts to ~62.14 miles")

        let unitMin = CommandBarUnits.convert("60 мин в ч", decimalSeparator: ",", groupingSeparator: " ", locale: ruRU)
        suite.expect(unitMin.map { abs($0.value - 1.0) < 0.001 } == true, "60 мин в ч converts to 1 hour")

        let unitGb = CommandBarUnits.convert("5 gb в mb", decimalSeparator: ".", groupingSeparator: ",", locale: enUS)
        suite.expect(unitGb.map { abs($0.value - 5000.0) < 0.001 } == true, "5 gb в mb converts to 5000 mb")
    }
}
