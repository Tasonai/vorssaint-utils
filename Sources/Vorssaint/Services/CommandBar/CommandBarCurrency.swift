// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Fast offline currency conversion for the command bar: "100 usd to eur",
/// "$50 in rub", "1000 ₽ в usd", "50 btc to usd", "100 eur > gbp".
///
/// Evaluates queries instantly using baseline reference exchange rates,
/// formatted with locale-aware symbols and precision.
enum CommandBarCurrency {
    struct Result: Equatable {
        /// The converted numeric value in target currency.
        let value: Double
        /// The formatted display string (e.g. "92,00 €" or "$108.70").
        let formatted: String
        /// Concise exchange rate ratio (e.g. "1 USD ≈ 0.92 EUR").
        let rateSummary: String
        let sourceCode: String
        let targetCode: String
        let sourceSymbol: String
        let targetSymbol: String
    }

    struct CurrencyInfo: Equatable {
        let code: String
        let symbol: String
        let name: String
        let rateToUSD: Double // Units of this currency per 1 USD
        let isPrefixSymbol: Bool
    }

    /// Primary currency definitions with baseline reference exchange rates.
    static let currencies: [String: CurrencyInfo] = [
        "USD": CurrencyInfo(code: "USD", symbol: "$", name: "US Dollar", rateToUSD: 1.0, isPrefixSymbol: true),
        "EUR": CurrencyInfo(code: "EUR", symbol: "€", name: "Euro", rateToUSD: 0.92, isPrefixSymbol: false),
        "RUB": CurrencyInfo(code: "RUB", symbol: "₽", name: "Russian Ruble", rateToUSD: 95.0, isPrefixSymbol: false),
        "GBP": CurrencyInfo(code: "GBP", symbol: "£", name: "British Pound", rateToUSD: 0.79, isPrefixSymbol: true),
        "JPY": CurrencyInfo(code: "JPY", symbol: "¥", name: "Japanese Yen", rateToUSD: 155.0, isPrefixSymbol: true),
        "CNY": CurrencyInfo(code: "CNY", symbol: "¥", name: "Chinese Yuan", rateToUSD: 7.25, isPrefixSymbol: true),
        "CHF": CurrencyInfo(code: "CHF", symbol: "CHF", name: "Swiss Franc", rateToUSD: 0.90, isPrefixSymbol: false),
        "CAD": CurrencyInfo(code: "CAD", symbol: "CA$", name: "Canadian Dollar", rateToUSD: 1.38, isPrefixSymbol: true),
        "AUD": CurrencyInfo(code: "AUD", symbol: "AU$", name: "Australian Dollar", rateToUSD: 1.52, isPrefixSymbol: true),
        "INR": CurrencyInfo(code: "INR", symbol: "₹", name: "Indian Rupee", rateToUSD: 84.0, isPrefixSymbol: true),
        "BRL": CurrencyInfo(code: "BRL", symbol: "R$", name: "Brazilian Real", rateToUSD: 5.65, isPrefixSymbol: true),
        "TRY": CurrencyInfo(code: "TRY", symbol: "₺", name: "Turkish Lira", rateToUSD: 34.2, isPrefixSymbol: false),
        "KRW": CurrencyInfo(code: "KRW", symbol: "₩", name: "South Korean Won", rateToUSD: 1380.0, isPrefixSymbol: true),
        "KZT": CurrencyInfo(code: "KZT", symbol: "₸", name: "Kazakhstani Tenge", rateToUSD: 490.0, isPrefixSymbol: false),
        "UAH": CurrencyInfo(code: "UAH", symbol: "₴", name: "Ukrainian Hryvnia", rateToUSD: 41.5, isPrefixSymbol: false),
        "BYN": CurrencyInfo(code: "BYN", symbol: "Br", name: "Belarusian Ruble", rateToUSD: 3.25, isPrefixSymbol: false),
        "AED": CurrencyInfo(code: "AED", symbol: "AED", name: "UAE Dirham", rateToUSD: 3.67, isPrefixSymbol: false),
        "THB": CurrencyInfo(code: "THB", symbol: "฿", name: "Thai Baht", rateToUSD: 34.5, isPrefixSymbol: false),
        "GEL": CurrencyInfo(code: "GEL", symbol: "₾", name: "Georgian Lari", rateToUSD: 2.75, isPrefixSymbol: false),
        "AMD": CurrencyInfo(code: "AMD", symbol: "֏", name: "Armenian Dram", rateToUSD: 388.0, isPrefixSymbol: false),
        "PLN": CurrencyInfo(code: "PLN", symbol: "zł", name: "Polish Zloty", rateToUSD: 4.05, isPrefixSymbol: false),
        "CZK": CurrencyInfo(code: "CZK", symbol: "Kč", name: "Czech Koruna", rateToUSD: 23.5, isPrefixSymbol: false),
        "ILS": CurrencyInfo(code: "ILS", symbol: "₪", name: "Israeli Shekel", rateToUSD: 3.70, isPrefixSymbol: true),
        "SEK": CurrencyInfo(code: "SEK", symbol: "kr", name: "Swedish Krona", rateToUSD: 10.6, isPrefixSymbol: false),
        "NOK": CurrencyInfo(code: "NOK", symbol: "kr", name: "Norwegian Krone", rateToUSD: 10.9, isPrefixSymbol: false),
        "DKK": CurrencyInfo(code: "DKK", symbol: "kr", name: "Danish Krone", rateToUSD: 6.88, isPrefixSymbol: false),
        "SGD": CurrencyInfo(code: "SGD", symbol: "SG$", name: "Singapore Dollar", rateToUSD: 1.32, isPrefixSymbol: true),
        "HKD": CurrencyInfo(code: "HKD", symbol: "HK$", name: "Hong Kong Dollar", rateToUSD: 7.78, isPrefixSymbol: true),
        "MXN": CurrencyInfo(code: "MXN", symbol: "Mex$", name: "Mexican Peso", rateToUSD: 19.8, isPrefixSymbol: true),
        "BTC": CurrencyInfo(code: "BTC", symbol: "BTC", name: "Bitcoin", rateToUSD: 0.0000147, isPrefixSymbol: false),
        "ETH": CurrencyInfo(code: "ETH", symbol: "ETH", name: "Ethereum", rateToUSD: 0.0004, isPrefixSymbol: false),
        "SOL": CurrencyInfo(code: "SOL", symbol: "SOL", name: "Solana", rateToUSD: 0.00555, isPrefixSymbol: false),
        "TON": CurrencyInfo(code: "TON", symbol: "TON", name: "Toncoin", rateToUSD: 0.185, isPrefixSymbol: false),
        "USDT": CurrencyInfo(code: "USDT", symbol: "USDT", name: "Tether", rateToUSD: 1.0, isPrefixSymbol: false),
        "USDC": CurrencyInfo(code: "USDC", symbol: "USDC", name: "USD Coin", rateToUSD: 1.0, isPrefixSymbol: false),
    ]

    private static let currencySymbols: Set<Character> = [
        "$", "€", "£", "¥", "₽", "₹", "₺", "₩", "₸", "₴", "฿", "₾", "֏", "₿", "元"
    ]

    /// Multilingual lexicon mapping folded keywords, symbols, and slang to ISO currency codes.
    private static let lexicon: [String: String] = {
        var map: [String: String] = [:]
        func register(_ words: [String], code: String) {
            for word in words {
                map[CommandBarSearch.normalized(word)] = code
            }
        }

        register(["usd", "$", "dollar", "dollars", "dolar", "dolares", "доллар", "доллара",
                  "долларов", "доллары", "бакс", "бакса", "баксов", "баксы", "зеленый", "зеленых", "зеленые"], code: "USD")
        register(["eur", "€", "euro", "euros", "евро"], code: "EUR")
        register(["rub", "rur", "₽", "ruble", "rubles", "рубль", "рубля", "рублей", "рубли",
                  "руб", "деревянный", "деревянных"], code: "RUB")
        register(["gbp", "£", "pound", "pounds", "sterling", "фунт", "фунта", "фунтов", "фунты",
                  "стерлинг", "стерлингов"], code: "GBP")
        register(["jpy", "¥", "yen", "yens", "иена", "иены", "иен", "йена", "йены", "йен"], code: "JPY")
        register(["cny", "rmb", "yuan", "юань", "юаня", "юаней", "юани", "元"], code: "CNY")
        register(["chf", "franc", "francs", "франк", "франка", "франков", "франки"], code: "CHF")
        register(["cad", "ca$", "loonie", "канадский доллар"], code: "CAD")
        register(["aud", "au$", "австралийский доллар"], code: "AUD")
        register(["inr", "₹", "rupee", "rupees", "рупия", "рупии", "рупий"], code: "INR")
        register(["brl", "r$", "real", "reais", "реал", "реалов"], code: "BRL")
        register(["try", "₺", "lira", "лира", "лиры", "лир"], code: "TRY")
        register(["krw", "₩", "won", "вона", "воны", "вон"], code: "KRW")
        register(["kzt", "₸", "tenge", "тенге"], code: "KZT")
        register(["uah", "₴", "hryvnia", "гривна", "гривны", "гривен"], code: "UAH")
        register(["byn", "белорусский рубль", "белорусских рублей"], code: "BYN")
        register(["aed", "dirham", "дирхам", "дирхама", "дирхамов"], code: "AED")
        register(["thb", "฿", "baht", "бат", "бата", "батов"], code: "THB")
        register(["gel", "₾", "lari", "лари"], code: "GEL")
        register(["amd", "֏", "dram", "драм", "драма", "драмов"], code: "AMD")
        register(["pln", "zł", "zloty", "злотый", "злотых"], code: "PLN")
        register(["czk", "kč", "koruna", "крона", "кроны", "крон"], code: "CZK")
        register(["ils", "₪", "shekel", "шекель", "шекелей"], code: "ILS")
        register(["sek", "шведская крона"], code: "SEK")
        register(["nok", "норвежская крона"], code: "NOK")
        register(["dkk", "датская крона"], code: "DKK")
        register(["sgd", "sg$", "сингапурский доллар"], code: "SGD")
        register(["hkd", "hk$", "гонконгский доллар"], code: "HKD")
        register(["mxn", "песо"], code: "MXN")
        register(["btc", "₿", "bitcoin", "биткоин", "биткоина", "биткоинов", "биток", "битка"], code: "BTC")
        register(["eth", "Ξ", "ethereum", "ether", "эфир", "эфириум", "эфира"], code: "ETH")
        register(["sol", "solana", "солана", "соланы"], code: "SOL")
        register(["ton", "тон", "тона"], code: "TON")
        register(["usdt", "тезер", "тизер", "tether"], code: "USDT")
        register(["usdc"], code: "USDC")
        return map
    }()

    /// Evaluates currency conversion for `input`, or returns nil if input is not a currency query.
    static func convert(_ input: String,
                        decimalSeparator: String = Locale.current.decimalSeparator ?? ".",
                        groupingSeparator: String = Locale.current.groupingSeparator ?? ",",
                        locale: Locale = .current) -> Result? {
        let tokens = tokenize(input)
        guard tokens.count >= 2, tokens.count <= 6 else { return nil }

        // Form 1: [amount, sourceCurrency, verb, targetCurrency] e.g. "100 usd in eur", "100 $ to rub"
        // Form 2: [sourceCurrency, amount, verb, targetCurrency] e.g. "$ 100 in eur"
        // Form 3: [amount, sourceCurrency, targetCurrency] e.g. "100 usd eur"
        // Form 4: [sourceCurrency, amount, targetCurrency] e.g. "$ 100 eur"

        guard let parsed = parseStructure(tokens: tokens,
                                          decimalSeparator: decimalSeparator,
                                          groupingSeparator: groupingSeparator)
        else { return nil }

        guard parsed.source != parsed.target else { return nil }
        guard let sourceCurrency = currencies[parsed.source],
              let targetCurrency = currencies[parsed.target]
        else { return nil }

        let usdAmount = parsed.amount / sourceCurrency.rateToUSD
        let targetValue = usdAmount * targetCurrency.rateToUSD
        guard targetValue.isFinite, !targetValue.isNaN else { return nil }

        let formatted = format(value: targetValue, currency: targetCurrency, locale: locale)
        let rate1InTarget = (1.0 / sourceCurrency.rateToUSD) * targetCurrency.rateToUSD
        let rateSummary = formatRate(source: sourceCurrency, target: targetCurrency, rate: rate1InTarget, locale: locale)

        return Result(
            value: targetValue,
            formatted: formatted,
            rateSummary: rateSummary,
            sourceCode: sourceCurrency.code,
            targetCode: targetCurrency.code,
            sourceSymbol: sourceCurrency.symbol,
            targetSymbol: targetCurrency.symbol
        )
    }

    private struct ParsedQuery {
        let amount: Double
        let source: String
        let target: String
    }

    private static func parseStructure(tokens: [String],
                                       decimalSeparator: String,
                                       groupingSeparator: String) -> ParsedQuery? {
        // Try pattern with conversion verb:
        // Position of verb can be from 1 to tokens.count - 2
        for pos in 1..<(tokens.count - 1) {
            let candidateVerb = tokens[pos]
            if CommandBarUnits.conversionWords.contains(candidateVerb) {
                let leftTokens = Array(tokens[0..<pos])
                let rightTokens = Array(tokens[(pos + 1)...])
                guard let target = currencyCode(for: rightTokens),
                      let (amount, source) = parseAmountAndCurrency(tokens: leftTokens,
                                                                    decimalSeparator: decimalSeparator,
                                                                    groupingSeparator: groupingSeparator)
                else { continue }
                return ParsedQuery(amount: amount, source: source, target: target)
            }
        }

        // Shorthand pattern without conversion verb:
        // E.g. [amount, source, target] or [source, amount, target]
        if tokens.count >= 3 {
            // Case 1: [amount, source, target]
            if let target = currencyCode(for: [tokens.last!]),
               let (amount, source) = parseAmountAndCurrency(tokens: Array(tokens.dropLast()),
                                                             decimalSeparator: decimalSeparator,
                                                             groupingSeparator: groupingSeparator) {
                return ParsedQuery(amount: amount, source: source, target: target)
            }
        }

        return nil
    }

    private static func currencyCode(for tokens: [String]) -> String? {
        let joined = tokens.joined(separator: " ")
        return lexicon[joined] ?? lexicon[tokens.first ?? ""]
    }

    private static func parseAmountAndCurrency(tokens: [String],
                                               decimalSeparator: String,
                                               groupingSeparator: String) -> (Double, String)? {
        guard !tokens.isEmpty, tokens.count <= 3 else { return nil }

        // [amount, currency...]
        if let val = number(tokens[0], decimalSeparator: decimalSeparator, groupingSeparator: groupingSeparator),
           let code = currencyCode(for: Array(tokens.dropFirst())) {
            return (val, code)
        }

        // [currency..., amount]
        if let last = tokens.last,
           let val = number(last, decimalSeparator: decimalSeparator, groupingSeparator: groupingSeparator),
           let code = currencyCode(for: Array(tokens.dropLast())) {
            return (val, code)
        }

        return nil
    }

    /// Splits input into cleanly isolated tokens, recognizing prefix/suffix symbols.
    static func tokenize(_ input: String) -> [String] {
        let folded = CommandBarSearch.normalized(input)
        var rawTokens: [String] = []

        for word in folded.split(whereSeparator: \.isWhitespace).map(String.init) {
            // Leading currency symbol e.g. "$100", "€50", "₽1000"
            if let first = word.first, currencySymbols.contains(first) {
                let sym = String(first)
                let rest = String(word.dropFirst())
                rawTokens.append(sym)
                if !rest.isEmpty {
                    // Check if rest contains numbers or other tokens
                    rawTokens.append(contentsOf: splitNumberAndRest(rest))
                }
                continue
            }

            // Trailing currency symbol e.g. "100$", "50€", "1000₽"
            if let last = word.last, currencySymbols.contains(last) {
                let sym = String(last)
                let prefix = String(word.dropLast())
                if !prefix.isEmpty {
                    rawTokens.append(contentsOf: splitNumberAndRest(prefix))
                }
                rawTokens.append(sym)
                continue
            }

            // Combined number and currency letters e.g. "100usd", "50eur"
            if let first = word.first, first.isNumber || first == "." || first == "," || first == "-" {
                rawTokens.append(contentsOf: splitNumberAndRest(word))
                continue
            }

            rawTokens.append(word)
        }

        return rawTokens
    }

    private static func splitNumberAndRest(_ token: String) -> [String] {
        let digits = token.prefix { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        let rest = String(token.dropFirst(digits.count))
        var result: [String] = []
        if !digits.isEmpty { result.append(String(digits)) }
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    /// Parses numbers with locale-aware grouping and decimal separators.
    private static func number(_ token: String,
                               decimalSeparator: String,
                               groupingSeparator: String) -> Double? {
        let groupsWithPunctuation = (groupingSeparator == "." || groupingSeparator == ",")
            && groupingSeparator != decimalSeparator
        let alternate = groupsWithPunctuation ? groupingSeparator : (decimalSeparator == "," ? "." : ",")
        var normalized = token
        let hasDecimal = token.contains(decimalSeparator)
        let hasAlternate = token.contains(alternate)

        if hasDecimal, hasAlternate {
            let decimalRange = token.range(of: decimalSeparator, options: .backwards)
            let alternateRange = token.range(of: alternate, options: .backwards)
            if let decimalRange, let alternateRange, alternateRange.lowerBound > decimalRange.lowerBound {
                normalized = token.replacingOccurrences(of: decimalSeparator, with: "")
                    .replacingOccurrences(of: alternate, with: ".")
            } else {
                normalized = token.replacingOccurrences(of: alternate, with: "")
                    .replacingOccurrences(of: decimalSeparator, with: ".")
            }
        } else if hasAlternate {
            let unsigned = token.hasPrefix("-") ? String(token.dropFirst()) : token
            let groups = unsigned.components(separatedBy: alternate)
            let isGrouping = groups.count >= 2 && (1...3).contains(groups[0].count)
                && !groups[0].hasPrefix("0")
                && groups.dropFirst().allSatisfy { $0.count == 3 }
            normalized = token.replacingOccurrences(of: alternate, with: isGrouping ? "" : ".")
        } else if hasDecimal {
            normalized = token.replacingOccurrences(of: decimalSeparator, with: ".")
        }

        guard !normalized.isEmpty, normalized.filter({ $0 == "." }).count <= 1,
              normalized.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" })
        else { return nil }
        return Double(normalized)
    }

    /// Formats a converted amount with appropriate precision and currency placement.
    static func format(value: Double, currency: CurrencyInfo, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true

        let isCrypto = currency.code == "BTC" || currency.code == "ETH" || currency.code == "SOL"
        if isCrypto {
            formatter.maximumFractionDigits = 6
            formatter.minimumFractionDigits = 2
        } else if abs(value) < 1 {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        }

        let numStr = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", locale: locale, value)
        if currency.isPrefixSymbol {
            return "\(currency.symbol)\(numStr)"
        } else {
            return "\(numStr) \(currency.symbol)"
        }
    }

    /// Formats the exchange rate reference summary.
    private static func formatRate(source: CurrencyInfo,
                                   target: CurrencyInfo,
                                   rate: Double,
                                   locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true

        let isTargetCrypto = target.code == "BTC" || target.code == "ETH" || target.code == "SOL"
        if isTargetCrypto || rate < 0.01 {
            formatter.maximumFractionDigits = 6
            formatter.minimumFractionDigits = 2
        } else if rate < 1 {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        }

        let rateStr = formatter.string(from: NSNumber(value: rate)) ?? String(format: "%.2f", locale: locale, rate)
        return "1 \(source.code) ≈ \(rateStr) \(target.code)"
    }
}
