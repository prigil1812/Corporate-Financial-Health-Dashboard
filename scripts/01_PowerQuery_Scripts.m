// =====================================================================
// POWER QUERY (M) SCRIPTS: Financial Statements project
// How to use: Home > Get Data > Blank Query > Advanced Editor.
// Paste ONE block per query, then rename the query exactly as shown
// in the header of each block. Update the FilePath in stgFinancials.
// =====================================================================


// ---------------------------------------------------------------------
// QUERY 1: stgFinancials   (right-click > untick "Enable load")
// Cleans the raw CSV. Everything else builds on this.
// ---------------------------------------------------------------------
let
    FilePath = "C:\Users\YourName\Downloads\Financial_Statements.csv",

    Source = Csv.Document(
        File.Contents(FilePath),
        [Delimiter = ",", Columns = 23, Encoding = 65001, QuoteStyle = QuoteStyle.None]
    ),
    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),

    // Fix hidden BOM character + trailing spaces in headers (e.g. "Company ")
    TrimmedHeaders = Table.TransformColumnNames(
        Promoted, each Text.Trim(Text.Replace(_, "#(feff)", ""))
    ),

    // Short, DAX-friendly column names
    Renamed = Table.RenameColumns(TrimmedHeaders, {
        {"Company", "Ticker"},
        {"Market Cap(in B USD)", "MarketCap_BUSD"},
        {"Gross Profit", "GrossProfit"},
        {"Net Income", "NetIncome"},
        {"Earning Per Share", "EPS"},
        {"Share Holder Equity", "ShareholderEquity"},
        {"Cash Flow from Operating", "OperatingCF"},
        {"Cash Flow from Investing", "InvestingCF"},
        {"Cash Flow from Financial Activities", "FinancingCF"},
        {"Current Ratio", "CurrentRatio"},
        {"Debt/Equity Ratio", "DebtEquityRatio"},
        {"Net Profit Margin", "NetProfitMarginPct"},
        {"Free Cash Flow per Share", "FCFPerShare"},
        {"Return on Tangible Equity", "ROTE"},
        {"Number of Employees", "Employees"},
        {"Inflation Rate(in US)", "InflationRatePct"}
    }),

    // Standardise text: removes Bank/BANK style duplicates
    CleanText = Table.TransformColumns(Renamed, {
        {"Ticker",   each Text.Upper(Text.Trim(_)), type text},
        {"Category", each Text.Upper(Text.Trim(_)), type text}
    }),

    // Data types (en-US culture so decimals parse correctly)
    Typed = Table.TransformColumnTypes(CleanText, {
        {"Year", Int64.Type}, {"Employees", Int64.Type},
        {"MarketCap_BUSD", type number}, {"Revenue", type number},
        {"GrossProfit", type number}, {"NetIncome", type number},
        {"EPS", type number}, {"EBITDA", type number},
        {"ShareholderEquity", type number}, {"OperatingCF", type number},
        {"InvestingCF", type number}, {"FinancingCF", type number},
        {"CurrentRatio", type number}, {"DebtEquityRatio", type number},
        {"ROE", type number}, {"ROA", type number}, {"ROI", type number},
        {"NetProfitMarginPct", type number}, {"FCFPerShare", type number},
        {"ROTE", type number}, {"InflationRatePct", type number}
    }, "en-US"),

    // Remove empty rows and duplicate Ticker + Year combinations
    NoBlanks = Table.SelectRows(Typed, each [Ticker] <> null and [Ticker] <> "" and [Year] <> null),
    Deduped  = Table.Distinct(NoBlanks, {"Ticker", "Year"})
in
    Deduped


// ---------------------------------------------------------------------
// QUERY 2: FactFinancials   (the fact table, one row per company-year)
// ---------------------------------------------------------------------
let
    Source = stgFinancials,
    Removed = Table.RemoveColumns(Source, {"Category"}),
    Sorted = Table.Sort(Removed, {{"Ticker", Order.Ascending}, {"Year", Order.Ascending}})
in
    Sorted


// ---------------------------------------------------------------------
// QUERY 3: DimCompany   (one row per company)
// Company names and sector labels are added by lookup. The bankruptcy
// flag is MY addition (Sears 2018, PG&E 2019): verify before publishing.
// ---------------------------------------------------------------------
let
    Source = stgFinancials,

    Grouped = Table.Group(Source, {"Ticker"}, {
        {"RawCategory", each List.First(Table.Sort(_, {{"Year", Order.Descending}})[Category]), type text},
        {"FirstYear", each List.Min([Year]), Int64.Type},
        {"LastYear",  each List.Max([Year]), Int64.Type}
    }),

    Names = [
        AAPL = "Apple", AIG = "AIG", AMZN = "Amazon", BCS = "Barclays",
        GOOG = "Alphabet", INTC = "Intel", MCD = "McDonald's",
        MSFT = "Microsoft", NVDA = "NVIDIA", PCG = "PG&E",
        PYPL = "PayPal", SHLDQ = "Sears Holdings"
    ],
    Sectors = [
        IT = "Information Technology", FINTECH = "Fintech", BANK = "Banking",
        MANUFACTURING = "Manufacturing", FINANCE = "Finance",
        FOOD = "Food & Beverage", ELEC = "Electronics", LOGI = "Logistics & E-commerce"
    ],
    BankruptList = {"SHLDQ", "PCG"},

    AddName   = Table.AddColumn(Grouped, "Company", each Record.FieldOrDefault(Names, [Ticker], [Ticker]), type text),
    AddSector = Table.AddColumn(AddName, "Sector", each Record.FieldOrDefault(Sectors, [RawCategory], [RawCategory]), type text),
    AddFlag   = Table.AddColumn(AddSector, "Bankruptcy History", each if List.Contains(BankruptList, [Ticker]) then "Yes" else "No", type text),

    Final = Table.SelectColumns(AddFlag, {"Ticker", "Company", "Sector", "FirstYear", "LastYear", "Bankruptcy History"})
in
    Final


// ---------------------------------------------------------------------
// QUERY 4: DimYear   (one row per year, with a data-completeness flag)
// 2023 only has 2 companies, so it is marked "Partial".
// ---------------------------------------------------------------------
let
    Source = stgFinancials,
    Grouped = Table.Group(Source, {"Year"}, {{"CompanyCount", each Table.RowCount(_), Int64.Type}}),
    Flag = Table.AddColumn(Grouped, "YearStatus", each if [CompanyCount] < 5 then "Partial" else "Complete", type text),
    Sorted = Table.Sort(Flag, {{"Year", Order.Ascending}})
in
    Sorted
