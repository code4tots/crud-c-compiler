# Simple C Compiler in Ruby
require 'set'
require 'strscan'

class Ast
	attr_reader :type, :children
	def initialize type, children
		@type = type
		@children = children
	end
	
	def to_s
		inspect
	end
	
	def inspect
		"Ast(#{@type},#{@children})"
	end
	
	def [] i
		@children[i]
	end
	
	def generate_assembly ctx
		case @type
		when :translation_unit
			ctx['context'] = :global
			ctx['globals'] = ''
			ctx['assembly'] = "section .text\nglobal _start\n_start:\n\tcall _main\n\tpush eax\n\tmov eax, 0x1\n\tsub esp, 4\n\tint 0x80\n"
			@children.each{|ast| ast.generate_assembly(ctx)}
			ctx['assembly'] += "section .data\n"+ctx['globals']
		when :declaration_statement
			ctx['globals'] += "\t_#{@children[0].name} dd 0\n" # Right now, all variables are global.
		when :block_statement
			@children.each{|ast| ast.generate_assembly(ctx)}
		when :expression_statement
			ctx['context'] = :expression
			@children[0].generate_assembly(ctx)
			ctx['assembly'] += "\tpop eax\n"          # The statement is over. Pop the remaining argument.
		when :return_statement
			ctx['context'] = :expression
			@children[0].generate_assembly(ctx)       # At this point, the return value is on the top of the stack.
			ctx['assembly'] += "\tpop eax\n"          # store the return value at eax
			ctx['assembly'] += "\tret\n"
		when :function_definition
			ctx['context'] = :function_definition
			ctx['assembly'] += "_#{name}:\n"
			@children[1].generate_assembly(ctx)
		when :assignment
			@children[2].generate_assembly(ctx)                    # calculate and load the value on the stack
			ctx['assembly'] += "\tpop  dword [_#{@children[0].name}]\n"  # save the value to memory
			ctx['assembly'] += "\tpush dword [_#{@children[0].name}]\n"  # push that value right back onto the stack
		when :int
			ctx['assembly'] += "\tpush dword #{@children[0].value}\n"   # push the integer onto the stack
		when :id
			case ctx['context']
			when :expression
				ctx['assembly'] += "\tpush dword [_#{name}]\n"
			end
		when :binary_operation
			@children[0].generate_assembly(ctx) # first argument on stack
			@children[2].generate_assembly(ctx) # second argument on stack
			ctx['assembly'] += "\tpop ecx\n\tpop eax\n" # load the arguments to the registers
			cmd = case @children[1].value
			when '+'
				"add eax, ecx"
			end
			ctx['assembly'] += "\t#{cmd}\n\tpush eax\n"
		when :function_call
			ctx['assembly'] += "\tcall _#{@children[0].name}\n"    # No support for arguments just yet
			ctx['assembly'] += "\tpush eax\n"                      # Push the return value onto the stack
		end
		return ctx['assembly']
	end
	
	def name
		case @type
		when :function_definition
			return @children[0].name # ask the declaration what the name is
		when :declaration
			return @children[1].name # ask the declarator what the name is
		when :function_declarator
			return @children[0].name # ask the function part of the declarator what the name is
		when :pointer_declarator
			return @children[1].name # ask the pointee what the name is
		when :id
			return @children[0].value # ask the Token what its value is
		end
	end	
end



class Token
	attr_reader :type, :value
	def initialize type, value
		@type = type
		@value = value
	end
	def to_s
		@value
	end
	def inspect
		"Token(#{@type},#{@value})"
	end
end

class Lexer
	def lex string
		regexes = [
			[:float, /\d+\.\d*/ ],
			[:int, /\d+(?!\.)/]]
		tokens = []
		scanner = StringScanner.new string
		while true
			scanner.scan(/\s+/)     # skip whitespace
			break if scanner.eos?   # break if we've reached the end
			match_found = false

			# skip comments
			if scanner.scan(/\/\//)
				scanner.scan(/[^\n]*/)
				next
			end
			
			# check for float/int
			regexes.each do |(type,regex)|
				match = scanner.scan(regex)
				if match
					match_found = true
					tokens << Token.new(type,match)
					break
				end
			end
			next if match_found

			# check for symbols
			SYMBOLS.each do |symbol|
				match = scanner.scan(/#{Regexp.quote(symbol)}/)
				if match
					match_found = true
					tokens << Token.new(:symbol,match)
					break
				end
			end
			next if match_found
			
			# check for id/keywords
			match = scanner.scan(/\w+/)
			if match
				match_found = true
				tokens << Token.new((KEYWORDS.include?(match) ? :keyword : :id), match)
			end
			next if match_found

			# we've encountered an unknown token
			raise "Unrecognized token: #{scanner.scan(/\S+/)}"
		end
		tokens << Token.new(:eof,'')
		return tokens
	end
end

class TokenStream
	def initialize tokens
		@tokens = tokens
		@position = 0
	end
	
	def save
		@position
	end
	
	def load position
		@position = position
	end
	
	def peek
		@tokens[@position]
	end
	
	def next
		@position += 1
		@tokens[@position-1]
	end
end

class Parser
	def parse stream
		save = stream.save
		result = self._parse stream
		stream.load save if result == nil
		return result
	end
	
	def separated_by separator_parser
		SeparationParser.new self, separator_parser
	end
end

class Proxy < Parser
	attr_accessor :parser
	def _parse stream
		@parser.parse(stream)
	end
end

class TokenConditionMatcher < Parser
	def initialize condition
		@condition = condition
	end
	
	def _parse stream
		if @condition.call(stream.peek)
			return stream.next
		end
		nil
	end
end

class TokenValueMatcher < TokenConditionMatcher
	def initialize value
		super lambda {|token| token != nil && token.value == value }
	end
end

class TokenTypeMatcher < TokenConditionMatcher
	def initialize type
		super lambda {|token| token.type == type }
	end
end

class Action < Parser
	def initialize parser, action
		@parser = parser
		@action = action
	end
	
	def _parse stream
		result = @parser.parse(stream)
		if !result.nil?
			return @action.call(result)
		end
		return nil
	end
end

class Or < Parser
	def initialize parsers
		@parsers = parsers
	end
	
	def _parse stream
		@parsers.each do |parser|
			result = parser.parse(stream)
			return result if result != nil
		end
		return nil
	end
end

class And < Parser
	def initialize parsers, action
		@parsers = parsers
		@action = action
	end
	
	def _parse stream
		results = []
		@parsers.each do |parser|
			result = parser.parse(stream)
			return nil if result == nil
			results << result
		end
		return @action.call(results)
	end
end

class ZeroOrMore < Parser
	def initialize parser, action
		@parser = parser
		@action = action
	end
	
	def _parse stream
		results = []
		while true
			result = @parser.parse(stream)
			return @action.call(results) if result == nil
			results << result
		end
	end
end

class SeparationParser < Parser
	def initialize content_parser, separator_parser
		@content_parser = content_parser
		@separator_parser = separator_parser
		@pair_parser = And.new([separator_parser,content_parser],lambda {|(_,content)| content})
	end
	def _parse stream
		result = @content_parser.parse(stream)
		return [] if result == nil
		results = [result]
		while true
			result = @pair_parser.parse(stream)
			return results if result == nil
			results << result
		end
	end
end

class PrefixOperation < Parser
	def initialize prefix_parser, higher_priority_parser, action
		@prefix_parser = prefix_parser
		@prefixes_parser = ZeroOrMore.new(prefix_parser,lambda{|prs|prs})
		@higher_priority_parser = higher_priority_parser
		@action = action
	end
	
	def _parse stream
		prs = @prefixes_parser.parse(stream)
		e = @higher_priority_parser.parse(stream)
		return nil if e.nil?
		prs.reverse.each do |pr|
			e = @action.call(pr,e)
		end
		return e
	end
end

class PostfixOperation < Parser
	def initialize higher_priority_parser, postfix_parser, action
		@higher_priority_parser = higher_priority_parser
		@postfix_parser = postfix_parser
		@action = action
	end
	
	def _parse stream
		e = @higher_priority_parser.parse(stream)
		return nil if e == nil
		while true
			op = @postfix_parser.parse(stream)
			return e if op == nil
			e = @action.call(e,op)
		end
	end
end

class LeftAssociativeBinaryOperation < Parser
	def initialize higher_priority_parser, operator_parser, action
		@higher_priority_parser = higher_priority_parser
		@operator_parser = operator_parser
		@action = action
	end
	
	def _parse stream
		e = @higher_priority_parser.parse(stream)
		return nil if e == nil
		while true
			op = @operator_parser.parse(stream)
			return e if op == nil
			f = @higher_priority_parser.parse(stream)
			return nil if f == nil
			e = @action.call(e,op,f)
		end
	end
end

class Keyword < TokenValueMatcher
	def initialize keyword
		super keyword
		KEYWORDS << keyword
	end
end

class Symbol_ < TokenValueMatcher
	def initialize symbol
		super symbol
		SYMBOLS << symbol
	end
end

KEYWORDS = Set.new
SYMBOLS = Set.new

Expression = Proxy.new
Declaration = Proxy.new
Statement = Proxy.new

Id = Action.new(TokenTypeMatcher.new(:id),lambda{|tok| Ast.new(:id,[tok]) })
Int = Action.new(TokenTypeMatcher.new(:int),lambda{|tok| Ast.new(:int,[tok])})
Float_ = TokenTypeMatcher.new(:float)
ParentheticalExpression = And.new([Symbol_.new('('),Expression,Symbol_.new(')')],lambda{|(lp,e,rp)|e})
PrimaryExpression = Or.new([Id,Int,Float_,ParentheticalExpression])
ArgumentList = And.new([Symbol_.new('('),Declaration.separated_by(Symbol_.new(',')),Symbol_.new(')')],lambda{|(_,args,_)|args})
FunctionCall = PostfixOperation.new(PrimaryExpression,ArgumentList,lambda{|(f,args)|Ast.new(:function_call,[f,args])})
Expression.parser = LeftAssociativeBinaryOperation.new(
	LeftAssociativeBinaryOperation.new(
	FunctionCall,
	Or.new([Symbol_.new('+'),Symbol_.new('-')]),lambda{|lhs,op,rhs|Ast.new(:binary_operation,[lhs,op,rhs])}),
Symbol_.new('='),lambda{|lhs,eq_,rhs|Ast.new(:assignment,[lhs,eq_,rhs])})

Typeid = Or.new(['int','float','char'].collect{|t|Keyword.new(t)})
DeclaratorArgumentList = And.new([Symbol_.new('('),Declaration.separated_by(Symbol_.new(',')),Symbol_.new(')')], lambda {|(_,args,_)| args })
Declarator = PrefixOperation.new(
	Symbol_.new('*'),
	PostfixOperation.new(Id,DeclaratorArgumentList,lambda{|e,op| Ast.new(:function_declarator,[e,op])}),
	lambda {|op,e| Ast.new(:pointer_declarator,[op,e])})
Declaration.parser = And.new([Typeid,Declarator],lambda{|(t,d)| Ast.new(:declaration,[t,d])})

DeclarationStatement = And.new([Declaration,Symbol_.new(';')],lambda{|(decl,_)|Ast.new(:declaration_statement,[decl])})
ExpressionStatement = And.new([Expression,Symbol_.new(';')],lambda{|(e,_)|Ast.new(:expression_statement,[e])})
ReturnStatement = And.new([Keyword.new('return'),Expression,Symbol_.new(';')],lambda{|(_,e,_)|Ast.new(:return_statement,[e])})
BlockStatement = And.new([Symbol_.new('{'),ZeroOrMore.new(Statement,lambda{|ss|ss}),Symbol_.new('}')],lambda{|(_,ss,_)|Ast.new(:block_statement,ss)})
Statement.parser = Or.new([ReturnStatement,DeclarationStatement,ExpressionStatement,BlockStatement])

FunctionDefinition = And.new([Declaration,BlockStatement],lambda{|(decl,block)|Ast.new(:function_definition,[decl,block])})
Globals = Or.new([FunctionDefinition,DeclarationStatement])
TranslationUnit = And.new([ZeroOrMore.new(Globals,lambda{|ts| Ast.new(:translation_unit,ts)}),TokenTypeMatcher.new(:eof)],lambda{|(tu,_)|tu})

stream = TokenStream.new Lexer.new.lex <<-EOSEOS
int x;
int y;
int main() {
	x = 4;
	y = 7;
	return x+y;
}
EOSEOS
x = TranslationUnit.parse(stream)

puts x.generate_assembly({})
