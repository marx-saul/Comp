import data;
import std.algorithm, std.array, std.container, std.typecons;
import std.stdio: writeln;


// Grammar = Rule[]. See module "data"

// concat all the rules
Symbol[] concat(Rule[] rules) {
	Symbol[] symbols;
	foreach (rule; rules) {
		symbols ~= ( [ rule[0] ] ~ rule[1] );
	}
	return symbols;
}

@property int sym_num(Grammar grammar) {
	// return the maximum element
	return minCount!("a > b")(concat(grammar))[0] + 1;
}

// make a boolean table, true if nonterminal. false if terminal.
bool[] term_table(Rule[] rules) {
	bool[] table;
	table.length = rules.sym_num;
	
	foreach(rule; rules) {
		// rule[0] -> rule[1][0] rule[1][1] rule[1][2] ... rule[1][$-1]
		// mark nonterminal symbols as true 
		table[rule[0]] = true;
	}
	return table;
}

@property Symbol[] terminal(Rule[] rules) {
	bool[] table = term_table(rules);
	Symbol[] result;
	foreach(i, j; table) {
		if (!table[i]) result ~= [ cast(int)(i) ];
	}
	
	return result;
}

@property Symbol[] nonterminal(Rule[] rules) {
	bool[] table = term_table(rules);
	Symbol[] result;
	foreach(i, j; table) {
		if (table[i]) result ~= [ cast(int)(i) ];
	}
	
	return result;
}

// first(grammar)[a][b] <=> a in First(b)
bool[][Symbol] first(Grammar grammar) {
	bool[][Symbol] result;
	auto sym_num = grammar.sym_num;
	
	foreach (symbol; virtual .. sym_num) { result[symbol].length = sym_num; }
	foreach (symbol; grammar.terminal) { result[symbol][symbol] = true; }
	foreach (rule; grammar) {
		if (rule[1] == [empty_]) result[empty_][rule[0]] = true;
	}
	
	bool end;
	// add a into first(b)
	void add(Symbol a, Symbol b) {
		if (!result[a][b]) result[a][b] = true, end = false;
	}
	
	do {
		end = true;
		
		// rule = X -> Y1 Y2 Y3 Y4 ... Ym ... Yn
		foreach (rule; grammar) {
			int i;
			while (i < rule[1].length) {
				if (rule[1][i] == empty_) { ++i; continue; }
				
				// First(Yi) ⊆ First(X)
				foreach (symbol; -1 .. sym_num)
					if (result[symbol][rule[1][i]])
						add(symbol, rule[0]);
						
				// ε ∉ First(Yi)
				if (!result[empty_][rule[1][i]]) break;
				++i;
			}
			if (i == rule.length) add(empty_, rule[0]);
			
		}
		
	} while (!end);
	
	return result;
}

// first([x, y, ...])[s] <=> s ∈ First(xy...)
bool[Symbol] first(Grammar grammar, Symbol[] symbols, bool[][Symbol] first_table) {
	auto sym_num = grammar.sym_num;
	
	bool[Symbol] list;
	foreach (i; virtual .. sym_num) list[i] = false;
	
	auto add_empty = true;
	
	foreach (symbol; symbols) {
	
		if (symbol == end_of_file || symbol == virtual) { list[symbol] = true, add_empty = false; break; }
		foreach ( k; 0 .. sym_num ) {
			// k ∈ First(symbol)
			if (first_table[k][symbol]) list[k] = true;  
		}
		if (symbol != end_of_file && symbol != virtual && !first_table[empty_][symbol]) { add_empty = false; break; }
		
	}
	
	if (add_empty) list[empty_] = true;
	return list;
	/+
	Symbol[] result;
	foreach (symbol; empty_ .. sym_num) if (list[symbol]) result ~= symbol;
	return result;
	+/
}

// first([x,y, ... ]) = Fist(xy...)
Symbol[] first_list(Grammar grammar, Symbol[] symbols, bool[][Symbol] first_table) {
	auto list = first(grammar, symbols, first_table);
	Symbol[] result;
	foreach (symbol; virtual .. grammar.sym_num) {
		if (list[symbol]) result ~= symbol;
	}
	return result;
}

// follow(grammar)[a][b] <=> a in Follow(b)
bool[][Symbol] follow(Grammar grammar) {
	bool[][Symbol] result;
	auto sym_num = grammar.sym_num;
	auto first_table = first(grammar);
	
	auto terminal = grammar.terminal;
	auto is_nonterm = (Symbol x) => x>=0 && !canFind(terminal, x);
	
	
	foreach (symbol; 0 .. sym_num) { result[symbol].length = sym_num; }
	result[end_of_file].length = sym_num;
	result[end_of_file][0] = true;
	
	
	
	bool end;
	// add a into first(b)
	void add(Symbol a, Symbol b) {
		if (!result[a][b]) result[a][b] = true, end = false;
	}
	
	do {
		end = true;
		
		foreach (rule; grammar) foreach (i; 0 .. rule[1].length) {
			if (rule[1][i] == empty_ || !is_nonterm(rule[1][i])) continue;
			// A -> αBβ
			// First(β) ⊆ Follow(B)
			if ( i < rule[1].length-1 ) {
			
				auto f = first(grammar, rule[1][i+1..$], first_table);
				foreach (symbol; 0 .. sym_num) if (f[symbol]) add(symbol, rule[1][i]);
			
			}
			// A -> αB, ε ∈ First(β)
			// Follow(A) ⊆ Follow(B)
			if ( i == rule[1].length-1 || first(grammar, rule[1][i+1..$], first_table)[empty_] ) {
			
				if (result[end_of_file][rule[0]]) add(end_of_file, rule[1][i]);
				foreach (symbol; 0 .. sym_num) if (result[symbol][rule[0]]) add(symbol, rule[1][i]);
			
			}
		}
		
	} while (!end);
	
	return result;
}


class LRSyntaxAnalyzer {
	Grammar grammar;
	LRTable table;
	protected SList!ulong states_stack;
	this (Grammar g, LRTable t) {
		this.grammar = g, this.table = t;
		this.states_stack = SList!ulong(0);
	}
	
	abstract void reduce(ulong);
	abstract void shift(ulong);
	abstract Symbol next_token();
	
	
	public bool next() {
		static Symbol symbol = -3;
		if (symbol == -3) symbol = next_token();
		
		auto state = states_stack.front;
		auto entry = table[symbol][state];
		
		switch (entry[0]) {
		case Action.accept:
			return true;
			
		case Action.shift:
			states_stack.insert(entry[1]);
			shift(entry[1]);
			symbol = next_token();
			break;
			
		case Action.reduce:
			states_stack.removeFront(grammar[entry[1]][1].length);
			state = states_stack.front;
			states_stack.insert(table[ grammar[entry[1]][0] ][state] [1]); // goto(grammar[entry[1]][0], state)
			reduce(entry[1]);
			break;
			
		default: 
			throw new Exception("Syntax Error");
		}
		
		return false;
	}
}

/+
// return a table of whether a symbol can generate empty
bool[] generate_empty(Grammar grammar) {
	auto sym_num = grammar.sym_num;
	bool[] result; result.length = sym_num;
	
	bool end;
	void put(Symbol symbol) {
		if (!result[symbol]) result[symbol] = true, end = false;
	}
	
	do {
		end = true;
		foreach (symbol; 0 .. sym_num) foreach (rule; grammar) {
			if (rule[1] == [empty_]) put(rule[0]);
			
			// A -> [TSU]
			// map!(...) = [true, true, false]
			// ( T in result, S in result, U not in result )
			// if map!(...) contains only true (i.e. all the symbol produces ε)
			else if ( reduce!"a && b"(map!(x => result[x])(rule[1])) ) put(rule[0]);
		}
	} while (!end);
	
	return result;
}

// The result might contain empty_
Symbol[] first(Grammar grammar, Symbol symbol) {
	Symbol[] result = [symbol];
	
	auto sym_num = grammar.sym_num;
	// appeared checks if a certain symbol already appeared
	// to avoid infinite recuresive
	bool[] appeared; appeared.length = sym_num; //appeared[symbol] = false;
	
	auto is_empty_table = generate_empty(grammar);
	auto empty_reachable = (Symbol x) => x == empty_ || is_empty_table[x];
	
	auto terminal = grammar.terminal;
	auto is_term =    (Symbol x) => x>=0 &&  canFind(terminal, x);
	auto is_nonterm = (Symbol x) => x>=0 && !canFind(terminal, x);
	
	// do while there is a non-terminal symbols in result
	// for a non-terminal symbol A in result and for each A -> Xα
	// add X to result, and if appeard[X] == true, then since it has an enclosed cycle starting with X, remove X.
	while(true) {
		// loop over the non-terminals that have not appeared previously
		auto nonterms = filter!(x => is_nonterm(x) && !appeared[x])(result).array();
		if (nonterms.length == 0) break;
		
		foreach (sym; nonterms) { appeared[sym] = true; }
		foreach (sym; nonterms) foreach (rule; grammar) {
			if (rule[0] != sym) continue;
			// sym -> X0 X1 X2 ... Xm ... Xn
			// 0<=i<m  =>  Xi *->  ε 
			// m<=i    =>  Xi */-> ε
			
			auto m = countUntil!(x => !empty_reachable(x))(rule[1]);
			// foar all X, ε is in first(X)
			if (m == -1) result ~= [empty_];
			m = m == -1 ? rule[1].length-1 : m;
			result ~= rule[1][0 .. m+1];
		}
	}
	
	return filter!(x => is_term(x) || x == empty_)(result).array().sort().uniq().array();		// filtering is necessary because non-terminal symbols are not removed in the loop
}

Symbol[] first(Grammar grammar, Symbol[] symbols) {
	Symbol[] result;
	auto sym_num = grammar.sym_num;
	
	auto is_empty_table = generate_empty(grammar);
	auto empty_reachable = (Symbol x) => x == empty_ || is_empty_table[x];
	
	auto m = countUntil!(x => !empty_reachable(x))(symbols);
	if (m == -1) result ~= [empty_];
	m = m == -1 ? symbols.length-1 : m;
	
	// symbols = X0 X1 X2 ... Xm ... Xn
	// 0<=i<m  =>  Xi *->  ε 
	// m<=i    =>  Xi */-> ε
	// first(X1 X2 .. Xn) = first(X1) + first(X2) + ... + first(Xm)
	foreach (symbol; symbols[0..m+1]) {
		result ~= first(grammar, symbol);
	}
	
	return result.sort().uniq().array();
}

// The result may contain $ (the end of file)
Symbol[] follow(Grammar grammar, Symbol symbol) {
	Symbol[] result;
	
	// $ in follow(S)
	if (symbol == 0) result ~= [end_of_file];
	
	foreach (rule; grammar) {
		if (rule[0] = symbol) {
			result ~= first()
		}
	}
	
	return filter!(x => x != empty_)(result).array();
}
+/