# Branching

test_mod = Module()

#-------------------------------------------------------------------------------
@testset "Tail position" begin

@test JuliaLowering.include_string(test_mod, """
let a = true
    if a
        1
    end
end
""") === 1

@test JuliaLowering.include_string(test_mod, """
let a = false
    if a
        1
    end
end
""") === nothing

@test JuliaLowering.include_string(test_mod, """
let a = true
    if a
        1
    else
        2
    end
end
""") === 1

@test JuliaLowering.include_string(test_mod, """
let a = false
    if a
        1
    else
        2
    end
end
""") === 2

@test JuliaLowering.include_string(test_mod, """
let a = false, b = true
    if a
        1
    elseif b
        2
    else
        3
    end
end
""") === 2

@test JuliaLowering.include_string(test_mod, """
let a = false, b = false
    if a
        1
    elseif b
        2
    else
        3
    end
end
""") === 3

end

#-------------------------------------------------------------------------------
@testset "Value required but not tail position" begin

@test JuliaLowering.include_string(test_mod, """
let a = true
    x = if a
        1
    end
    x
end
""") === 1

@test JuliaLowering.include_string(test_mod, """
let a = false
    x = if a
        1
    end
    x
end
""") === nothing

@test JuliaLowering.include_string(test_mod, """
let a = true
    x = if a
        1
    else
        2
    end
    x
end
""") === 1

@test JuliaLowering.include_string(test_mod, """
let a = false
    x = if a
        1
    else
        2
    end
    x
end
""") === 2

@test JuliaLowering.include_string(test_mod, """
let a = false, b = true
    x = if a
        1
    elseif b
        2
    else
        3
    end
    x
end
""") === 2

@test JuliaLowering.include_string(test_mod, """
let a = false, b = false
    x = if a
        1
    elseif b
        2
    else
        3
    end
    x
end
""") === 3

end

#-------------------------------------------------------------------------------
@testset "Side effects (not value or tail position)" begin

@test JuliaLowering.include_string(test_mod, """
let a = true
    x = nothing
    if a
        x = 1
    end
    x
end
""") === 1

@test JuliaLowering.include_string(test_mod, """
let a = false
    x = nothing
    if a
        x = 1
    end
    x
end
""") === nothing

@test JuliaLowering.include_string(test_mod, """
let a = true
    x = nothing
    if a
        x = 1
    else
        x = 2
    end
    x
end
""") === 1

@test JuliaLowering.include_string(test_mod, """
let a = false
    x = nothing
    if a
        x = 1
    else
        x = 2
    end
    x
end
""") === 2

@test JuliaLowering.include_string(test_mod, """
let a = false, b = true
    x = nothing
    if a
        x = 1
    elseif b
        x = 2
    else
        x = 3
    end
    x
end
""") === 2

@test JuliaLowering.include_string(test_mod, """
let a = false, b = false
    x = nothing
    if a
        x = 1
    elseif b
        x = 2
    else
        x = 3
    end
    x
end
""") === 3

end
#-------------------------------------------------------------------------------
# Block condition
@test JuliaLowering.include_string(test_mod, """
let a = true
    if begin; x = 2; a; end
        x
    end
end
""") === 2

@testset "(AI) block conditions" begin
    # An empty block as a condition evaluates to `nothing` and must throw a
    # runtime TypeError (as the flisp lowering does for `if begin end`), not
    # crash lowering.
    @test_throws TypeError jl_eval(test_mod, Expr(:if, Expr(:block), 1, 2))
    @test_throws TypeError jl_eval(test_mod, Expr(:while, Expr(:block), 1))
    @test_throws TypeError JuliaLowering.include_string(test_mod, """
    (begin end) ? 1 : 2
    """)
    # ... including as a term of a `&&` chain
    @test_throws TypeError JuliaLowering.include_string(test_mod, """
    if (begin end) && true
        1
    else
        2
    end
    """)

    # do not ignore block[1:end-1]
    @test JuliaLowering.include_string(test_mod, """
    let a = true
        if (nothing; x = 2; a)
            x
        end
    end
    """) === 2

    # In a `while`, the whole block re-runs on every iteration, including the
    # final iteration that exits the loop.
    @test JuliaLowering.include_string(test_mod, """
    let s = 0, i = 0
        while (i = i + 1; i <= 3)
            s = s + i
        end
        (s, i)
    end
    """) === (6, 4)
    @test JuliaLowering.include_string(test_mod, """
    let log = []
        i = 0
        while (push!(log, :cond); i = i + 1; i <= 2 && true)
            push!(log, :body)
        end
        (i, log)
    end
    """) == (3, [:cond, :body, :cond, :body, :cond])

    # A non-final non-Bool term of a `&&` ending a multi-statement block
    # condition still throws TypeError (whether or not the chain gets the
    # direct-jump lowering).
    fnb = JuliaLowering.include_string(test_mod, """
    function ()
        if (nothing; 1 && true)
            1
        else
            2
        end
    end
    """)
    @test_throws TypeError fnb()

    # A multi-statement block as a *term* of a `&&` chain is not flattened and
    # must stay lazy: its statements run only if earlier terms pass.
    @test JuliaLowering.include_string(test_mod, """
    let log = []
        f(v) = (push!(log, v); v)
        r = if f(true) && (f(:pre); f(false))
            1
        else
            2
        end
        (r, log)
    end
    """) == (2, [true, :pre, false])
    @test JuliaLowering.include_string(test_mod, """
    let log = []
        f(v) = (push!(log, v); v)
        r = if f(false) && (f(:pre); f(true))
            1
        else
            2
        end
        (r, log)
    end
    """) == (2, [false])

    # Degenerate 0-arg `&&`/`||` as the final statement of a multi-statement
    # block condition
    @test jl_eval(test_mod, Expr(:if, Expr(:block, :(1 + 1), Expr(:&&)), 1, 2)) === 1
    @test jl_eval(test_mod, Expr(:if, Expr(:block, :(1 + 1), Expr(:||)), 1, 2)) === 2

    @test JuliaLowering.include_string(test_mod, """
    if begin begin true end end
        1
    else
        2
    end
    """) === 1
end

#-------------------------------------------------------------------------------
@testset "`&&` and `||` chains" begin

# 0-1 arguments
@test jl_eval(test_mod, Expr(:&&)) == true
@test jl_eval(test_mod, Expr(:&&, true)) == true
@test jl_eval(test_mod, Expr(:&&, false)) == false
@test jl_eval(test_mod, Expr(:||)) == false
@test jl_eval(test_mod, Expr(:||, true)) == true
@test jl_eval(test_mod, Expr(:||, false)) == false

# 0-1 arguments in condition position (`expand_condition`, used by `if`/`while`)
# have their own desugaring path separate from the value-position case above.
@test jl_eval(test_mod, Expr(:if, Expr(:&&), 1, 2)) == 1
@test jl_eval(test_mod, Expr(:if, Expr(:&&, true), 1, 2)) == 1
@test jl_eval(test_mod, Expr(:if, Expr(:&&, false), 1, 2)) == 2
@test jl_eval(test_mod, Expr(:if, Expr(:||), 1, 2)) == 2
@test jl_eval(test_mod, Expr(:if, Expr(:||, true), 1, 2)) == 1
@test jl_eval(test_mod, Expr(:if, Expr(:||, false), 1, 2)) == 2

# Same, but with the condition inside a block (the `isblock` branch of
# `expand_condition`)
@test jl_eval(test_mod, Expr(:if, Expr(:block, Expr(:&&, true)), 1, 2)) == 1
@test jl_eval(test_mod, Expr(:if, Expr(:block, Expr(:||, false)), 1, 2)) == 2
@test jl_eval(test_mod, Expr(:if, Expr(:block, Expr(:&&)), 1, 2)) == 1

# Degenerate arities nested inside another `&&`/`||` (flattened away by
# `expand_cond_children`)
@test jl_eval(test_mod, Expr(:if, Expr(:&&, Expr(:&&)), 1, 2)) == 1
@test jl_eval(test_mod, Expr(:if, Expr(:&&, Expr(:&&, false), true), 1, 2)) == 2

# `while` conditions share `expand_condition` with `if`
@test jl_eval(test_mod, Expr(:while, Expr(:||), 1)) === nothing
@test jl_eval(test_mod, Expr(:while, Expr(:&&), Expr(:break))) === nothing

@test JuliaLowering.include_string(test_mod, """
true && "hi"
""") == "hi"

@test JuliaLowering.include_string(test_mod, """
true && true && "hi"
""") == "hi"

@test JuliaLowering.include_string(test_mod, """
false && "hi"
""") == false

@test JuliaLowering.include_string(test_mod, """
true && false && "hi"
""") == false

@test JuliaLowering.include_string(test_mod, """
begin
    z = true && "hi"
    z
end
""") == "hi"

@test JuliaLowering.include_string(test_mod, """
begin
    z = false && "hi"
    z
end
""") == false


@test JuliaLowering.include_string(test_mod, """
true || "hi"
""") == true

@test JuliaLowering.include_string(test_mod, """
true || true || "hi"
""") == true

@test JuliaLowering.include_string(test_mod, """
false || "hi"
""") == "hi"

@test JuliaLowering.include_string(test_mod, """
false || true || "hi"
""") == true

@test JuliaLowering.include_string(test_mod, """
false || false || "hi"
""") == "hi"

@test JuliaLowering.include_string(test_mod, """
begin
    z = false || "hi"
    z
end
""") == "hi"

@test JuliaLowering.include_string(test_mod, """
begin
    z = true || "hi"
    z
end
""") == true

end

@testset "symbolic goto/label" begin

JuliaLowering.include_string(test_mod, """
let
    a = []
    i = 1
    @label foo
    push!(a, i)
    i = i + 1
    if i <= 2
        @goto foo
    end
    a
end
""") == [1,2]

end
