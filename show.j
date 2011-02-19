# showing fundamental objects

print(x) = show(x)

show(tn::TypeName) = show(tn.name)

show(s::Symbol) = print(s)

function show_comma_array(ar, open, close)
    print(open)
    for i = 1:length(ar)
        show(ar[i])
        if i < length(ar)
            print(',')
        end
    end
    print(close)
end

function show(e::Expr)
    hd = e.head
    if is(hd,:call)
        print(e.args[1])
        show_comma_array(e.args[2:],'(',')')
    elseif is(hd,:(=))
        print("$(e.args[1]) = $(e.args[2])")
    elseif is(hd,:quote)
        a1 = e.args[1]
        if isa(e.args[1],Expr) && (is(a1.head,:body) ||
                                   is(a1.head,:block))
            println("\nquote")
            for a=a1.args
                println("  $a")
            end
            println("end")
        else
            if isa(a1,Symbol) && !is(a1,:(:))
                print(":$a1")
            else
                print(":($a1)")
            end
        end
    elseif is(hd,:null)
        print("()")
    elseif is(hd,:goto)
        print("goto $(e.args[1])")
    elseif is(hd,:gotoifnot)
        print("unless $(e.args[1]) goto $(e.args[2])")
    elseif is(hd,:label)
        print("$(e.args[1]): ")
    elseif is(hd,:return)
        print("return $(e.args[1])")
    elseif is(hd,:string)
        show(e.args[1])
    elseif is(hd,symbol("::"))
        print("$(e.args[1])::$(e.args[2])")
    elseif is(hd,:symbol)
        print(e.args[1])
    elseif is(hd,:body) || is(hd,:block)
        print("\nbegin\n")
        for a=e.args
            println("  $a")
        end
        println("end")
    else
        print(hd)
        show_comma_array(e.args,'(',')')
    end
    if !is(e.type, Any)
        if isa(e.type, FuncKind)
            print("::F")
        elseif is(e.type, IntrinsicFunction)
            print("::I")
        else
            print("::$(e.type)")
        end
    end
end

function show(e::TypeError)
    ctx = isempty(e.context) ? "" : "in $(e.context), "
    println("type error: $(e.func): ",
            "$(ctx)expected $(e.expected), ",
            "got $(typeof(e.got))")
end

function show(e::LoadError)
    show(e.error)
    println(" $(e.file):$(e.line)")
end

show(e::SystemError) = println("$(e.prefix): $(strerror(e.errnum))")
show(e::DivideByZeroError) = println("error: integer divide by zero")
show(e::StackOverflowError) = println("error: stack overflow")
show(e::EOFError) = println("read: end of file")
show(e::ErrorException) = println(e.msg)
show(e::KeyError) = println("key not found: $(e.key)")

function show(e::MethodError)
    name = ccall(:jl_genericfunc_name, Any, (Any,), e.f)
    println("no method $(name)$(typeof(e.args))")
end

dump(t::Type) = print(t)
dump(t::Tuple) = print(t)

function dump{T}(x::T)
    print(T,'(')
    for field = T.names
        print(field, '=')
        show(getfield(x, field))
        print(',')
    end
    println(')')
end

# show arrays
showempty{T}(a::Array{T}) = print("Array($T,$(size(a)))")

function showall{T}(a::Array{T,1})
    if isempty(a)
        return showempty(a)
    end
    if is(T,Any)
        opn = '{'; cls = '}'
    else
        opn = '['; cls = ']';
    end
    show_comma_array(a, opn, cls)
end

function showall{T}(a::Array{T,2})
    if isempty(a)
        return showempty(a)
    end
    for i = 1:size(a,1)
        show_cols(a, 1, size(a,2), i)
        print('\n')
    end
end

function show{T}(a::Array{T,1})
    if isempty(a)
        return showempty(a)
    end
    if is(T,Any)
        opn = '{'; cls = '}'
    else
        opn = '['; cls = ']';
    end
    n = size(a,1)
    if n <= 10
        show_comma_array(a, opn, cls)
    else
        show_comma_array(a[1:5], opn, "")
        print(",...,")
        show_comma_array(a[(n-4):n], "", cls)
    end
end

function show_cols(a, start, stop, i)
    for j = start:stop
        show(a[i,j])
        print(' ')
    end
end

function show{T}(a::Array{T,2})
    if isempty(a)
        return showempty(a)
    end
    m = size(a,1)
    n = size(a,2)
    print_hdots = false
    print_vdots = false
    if 10 < m; print_vdots = true; end
    if 10 < n; print_hdots = true; end
    if !print_vdots && !print_hdots
        for i = 1:m
            show_cols(a, 1, n, i)
            if i < m; println(); end
        end
    elseif print_vdots && !print_hdots
        for i = 1:3
            show_cols(a, 1, n, i)
            println()
        end
        println(':')
        for i = m-2:m
            show_cols(a, 1, n, i)
            if i < m; println(); end
        end
    elseif !print_vdots && print_hdots
        for i = 1:m
            show_cols(a, 1, 3, i)
            if i == 1 || i == m; print(": "); else; print("  "); end
            show_cols(a, n-2, n, i)
            if i < m; println(); end
        end
    else
        for i = 1:3
            show_cols(a, 1, 3, i)
            if i == 1; print(": "); else; print("  "); end
            show_cols(a, n-2, n, i)
            println()
        end
        print(":\n")
        for i = m-2:m
            show_cols(a, 1, 3, i)
            if i == m; print(": "); else; print("  "); end
            show_cols(a, n-2, n, i)
            if i < m; println(); end
        end
    end
end

show{T}(a::Array{T,0}) = print("Array($T,())")

function show(a::Array)
    if isempty(a)
        return showempty(a)
    end
    slice2d(a, idxs) = [ a[i, j, idxs...] | i=1:size(a,1), j=1:size(a,2) ]
    tail = size(a)[3:]
    cartesian_map(idxs->(print("[:, :, ");
                         for i = 1:(length(idxs)-1); print("$(idxs[i]), "); end;
                         println(idxs[length(idxs)], "] =");
                         print(slice2d(a, idxs), idxs == tail ? "" : "\n\n")),
                  map(x->Range1(1,x), tail))
end
