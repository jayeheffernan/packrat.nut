enum PR_STATEMENT_TYPE {
    RULE,
    DISCARD_NT,
    DISCARD_STRINGS,
    DISCARD_REGEXPS,
    NO_DISCARD_LOOKAHEADS,
};

Packrat.grammarGrammar <- Packrat.buildGrammar(function() {
    // Some little helpers
    rule("_")     / m(@"\s*");
    rule("__")    / m(@"\s+");
    rule("___")   / m(@"\s*\n(\n|\s)*");
    rule("arrow") / _ * "<-" * _;

    // Discard some matches that don't carry any information
    discard_strings();
    discard(___, __, _, arrow);

    // Types of RHS symbols
    // TODO make matching better for re and chars, so that they can include "/"
    // and "'"
    rule("re")          / "m/" * m("[^/]+") * "/";
    rule("chars")       / m(@"[^']*");
    rule("string")      / "'" * chars * "'";
    rule("identifier")  / rep([rule() / nla("m/") * nla("epsilon") - m(@"[a-zA-Z0-9_]")], 1);
    rule("nonterminal") / identifier;
    rule("composite")   / "(" * nt("ruleRhs") * ")" ;

    // Need to distinguish between repetitions and the rest of them
    rule("normalSymbol")
        / m(@"[+\-&!]") * nt("symbol")
        / nonterminal
        / composite
        / string
        / re;
    rule("repetition") / normalSymbol * m(@"[?*+]");

    // RHS symbol
    rule("symbol")
        / nla([ rule() / identifier * arrow / nt("meta")])
        * [ rule() / repetition / normalSymbol ];

    // Rules
    rule("ruleOptionSuffix")
        / __ * symbol * nt("ruleOptionSuffix")
        / epsilon;
    rule("ruleOption")
        / "epsilon"
        / symbol * ruleOptionSuffix;
    rule("ruleRhsSuffix")
        / _ * "/" * _ * nt("ruleRhs")
        / epsilon;
    rule("ruleRhs")    / ruleOption * ruleRhsSuffix;
    rule("ruleSuffix") / arrow * ruleRhs;
    rule("rule_")      / identifier * ruleSuffix;

    // Meta commands
    rule("idList") / identifier * rep([rule() / _ * "," * _ * identifier]);
    rule("meta")
        / "%" %"discard" * __ * idList
        / "%" %"discard_strings"
        / "%" %"discard_regexps"
        / "%" %"no_discard_lookaheads";

    // Grammar
    rule("statement") / [ rule() / ___ / START * _ ] * [ rule() / meta / rule_ ];
    rule("grammar")   / rep(statement) * _;
});

Packrat.grammarActions <- (function() {
    local S = PrSymbol;
    return {
        "whitespace": @(match) null,
        "chars": @(match) match.v[0].string,
        "string": @(match) S.str(match.v[0].v),
        "nonterminal": @(match) S.nt(match.v[0].v),
        "re": @(match) S.re(match.v[0].string),
        "composite": @(match) S.composite(match.v[0].v),
        "repetition": function(match) {
            assert(typeof match.v == "array");
            assert(match.v.len() == 2);
            assert(match.v[1].v == null)
            local sym = match.v[0].v;
            local repChar = match.v[1].string;
            local times = { "?": [0, 1], "*": [0, null], "+": [1, null] }[repChar];
            return S.rep(sym, times[0], times[1]);
        },
        "symbol": function(match) {
            local composite = match.v[0];
            assert(composite.t != PR_SYMBOL_TYPE.NEGATIVE_LOOKAHEAD);
            assert(typeof composite.v == "array");
            assert(composite.v.len() == 1);
            return composite.v[0].v;
        },
        "normalSymbol": function(match) {
            local sym = match.v[match.v.len()-1].v;
            if (match.alt == 0) {
                return {
                    "+": @() S.drop(sym, false),
                    "-": @() S.drop(sym),
                    "&": @() S.la(sym),
                    "!": @() S.nla(sym),
                }[match.v[0].string]();
            } else {
                return sym;
            }
        },
        "ruleOption": function(match) {
            if (match.alt == 0) {
                return [];
            } else {
                local sym = match.v[0].v;
                local rest = match.v[1].v;
                rest.insert(0, sym);
                return rest;
            }
        },
        "ruleOptionSuffix": function(match) {
            switch (match.alt) {
                case 0:
                    local sym = match.v[0].v;
                    local rest = match.v[1].v;
                    rest.insert(0, sym);
                    return rest;
                case 1:
                    return [];
                default:
                    throw "unexpected";
            }
        },
        "ruleRhs": function(match) {
            local ruleOption = match.v[0].v;
            local rest = match.v[1].v;
            rest.insert(0, ruleOption);
            return rest;
        },
        "ruleRhsSuffix": function(match) {
            switch (match.alt) {
                case 0:
                    return match.v[0].v;
                case 1:
                    return [];
                default:
                    throw "unexpected";
            }
        },
        "ruleSuffix": @(match) match.v[0].v,
        "identifier": @(match) match.string,
        "rule_": @(match) [PR_STATEMENT_TYPE.RULE, match.v[0].v, match.v[1].v]
        "idList": function(match) {
            local first = match.v[0].v;
            local rest = match.v[1].v.map(@(m) m.v[0].v);
            rest.insert(0, first);
            return rest;
        },
        "meta": function(match) {
            local type = {
                discard               = PR_STATEMENT_TYPE.DISCARD_NT,
                discard_strings       = PR_STATEMENT_TYPE.DISCARD_STRINGS,
                discard_regexps       = PR_STATEMENT_TYPE.DISCARD_REGEXPS,
                no_discard_lookaheads = PR_STATEMENT_TYPE.NO_DISCARD_LOOKAHEADS,
            }[match.v[0].string];
            local info = [type];

            if (match.alt == 0) {
                local ids = match.v[1].v;
                info.push(ids);
            }

            return info;
        },
        "statement": function(match) {
            assert(typeof match.v == "array")
            assert(match.v.len() == 2);
            local composite = match.v[1];
            assert(typeof composite.v == "array")
            assert(composite.v.len() == 1);
            local triplet = composite.v[0].v;
            return triplet;
        }
        "grammar": function(match) {
            local rules = {};
            local grammar = { discarded = {}, rules = {} };
            foreach (sub in match.v[0].v) {
                local statement = sub.v;
                local type = statement[0];
                if (type == PR_STATEMENT_TYPE.RULE) {
                    grammar.rules[statement[1]] <- statement[2]
                } else if (type == PR_STATEMENT_TYPE.DISCARD_NT) {
                    foreach (id in statement[1]) {
                        grammar.discarded[id] <- true;
                    }
                } else if (type == PR_STATEMENT_TYPE.DISCARD_STRINGS) {
                    grammar.discardStrings <- true;
                } else if (type == PR_STATEMENT_TYPE.DISCARD_REGEXPS) {
                    grammar.discardRegexps <- true;
                } else if (type == PR_STATEMENT_TYPE.NO_DISCARD_LOOKAHEADS) {
                    grammar.noDiscardLookaheads <- true;
                } else {
                    throw "unexpected";
                }
            }
            return grammar;
        },
    }
})();
