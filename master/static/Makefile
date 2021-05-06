args := '--keywords upper --identifiers lower --indent_width 4 --reindent --indent_columns'

fmt:
	find srv -name '*.sql' -type f | xargs -I{} -n1 echo sqlformat $(args) -o {} {}

check:
	find srv -name '*.sql' -type f | xargs -I{} echo sqlformat $(args) {}
