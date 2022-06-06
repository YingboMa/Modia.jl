using  Test
import DataFrames
import ForwardDiff
import FiniteDiff

macro usingModiaPlot()
    if haskey(ENV, "MODIA_PLOT")
        ModiaPlotPackage = ENV["MODIA_PLOT"]
        if !(ModiaPlotPackage in ModiaResult.AvailableModiaPlotPackages)
            @warn "ENV[\"MODIA_PLOT\"] = \"$ModiaPlotPackage\" is not supported!. Using \"NoPlot\"."
            @goto USE_NO_PLOT
        elseif ModiaPlotPackage == "NoPlot"
            @goto USE_NO_PLOT
        elseif ModiaPlotPackage == "SilentNoPlot"
            expr = :( import Modia.ModiaResult.SilentNoPlot: plot, showFigure, saveFigure, closeFigure, closeAllFigures )
            return esc( expr )
        else
            ModiaPlotPackage = Symbol("ModiaPlot_" * ModiaPlotPackage)
            expr = :(using $ModiaPlotPackage)
            println("$expr")
            return esc( :(using $ModiaPlotPackage) )
        end

    else
        @warn "No plot package activated. Using \"NoPlot\"."
        @goto USE_NO_PLOT
    end

    @label USE_NO_PLOT
    expr = :( import Modia.ModiaResult.NoPlot: plot, showFigure, saveFigure, closeFigure, closeAllFigures )
    println("$expr")
    return esc( expr )
end

#---------------------------------------------------------------------
#                          Simulation
#---------------------------------------------------------------------

function getAlgorithmName(algorithm)::String
    algorithmType = typeof(algorithm)
    if algorithmType == Missing
        return "???"
    end
    name = string(algorithmType)

    if algorithmType <: DifferentialEquations.OrdinaryDiffEq.QNDF
        if algorithm.kappa == tuple(0//1,0//1,0//1,0//1,0//1)
            name = replace(name, "QNDF" => "QBDF")
        end

    elseif algorithmType <: DifferentialEquations.OrdinaryDiffEq.QNDF1 ||
           algorithmType <: DifferentialEquations.OrdinaryDiffEq.QNDF2
        if algorithm.kappa == 0
            name = replace(name, "QNDF" => "QBDF")
        end
    end
    return name
end

"""
    solution = simulate!(instantiatedModel [, algorithm];
              merge            = missing,  # change parameter/init/start values
              tolerance        = 1e-6,     # relative tolerance
              startTime        = 0.0,
              stopTime         = 0.0,      # stopTime >= startTime required
              interval         = missing,  # = (stopTime-startTime)/500
              interp_points    = 0,
              dtmax            = missing,  # = 100*interval
              adaptive         = true,
              nlinearMinForDAE = 10,
              log              = false,
              logStates        = false,
              logEvents        = false,
              logProgress      = false,
              logTiming        = false,
              logParameters    = false,
              logEvaluatedParameters   = false,
              requiredFinalStates      = missing
              requiredFinalStates_rtol = 1e-3,
              requiredFinalStates_atol = 0.0,
              useRecursiveFactorizationUptoSize = 0)

Simulate `instantiatedModel::SimulationModel` with `algorithm`
(= `alg` of [ODE Solvers of DifferentialEquations.jl](https://diffeq.sciml.ai/stable/solvers/ode_solve/)
or [DAE Solvers of DifferentialEquations.jl](https://diffeq.sciml.ai/stable/solvers/dae_solve/)).

If the `algorithm` argument is missing, `algorithm=Sundials.CVODE_BDF()` is used, provided
instantiatedModel has `FloatType = Float64`. Otherwise, a default algorithm will be chosen from DifferentialEquations
(for details see [https://arxiv.org/pdf/1807.06430](https://arxiv.org/pdf/1807.06430), Figure 3).
The symbols `CVODE_BDF` and `IDA` are exported from Modia, so that `simulate!(instantiatedModel, CVODE_BDF(), ...)`
and `simulate!(instantiatedModel, IDA(), ...)`
can be used (instead of `import Sundials; simulate!(instantiatedModel, Sundials.xxx(), ...)`).

The simulation results are stored in `instantiatedModel` and can be plotted with
`plot(instantiatedModel, ...)` and the result values
can be retrieved with `rawSignal(..)` or `getPlotSignal(..)`. `printResultInfo(instantiatedModel)`
prints information about the signals in the result file.
For more details, see sections [Parameters/Init/Start](@ref), [Results](@ref), [Plotting](@ref).

The return argument `solution` is the return argument from `DifferentialEquations.solve(..)` and
therefore all post-processing functionality from `DifferentialEqautions.jl` can be used. Especially,
- solution.t[i] # time-instant at storage point i (solution.t[end] = stopTime)
- solution.u[i] # states at storage point i

A simulation run can be aborted with `<CTRL> C` (SIGINT), provided `using PyPlot` or `import PyPlot` was
not called before (the signals in Python module matplotlib.pyplot intervene with Julias signals, see
[PyPlot.jl issue 305](https://github.com/JuliaPy/PyPlot.jl/issues/305)).

# Optional ArgumentsS

- `merge`: Define parameters and init/start values that shall be merged with the previous values
           stored in `model`, before simulation is started. If, say, an init value `phi = Var(init=1.0)`
           is defined in the model, a different init value can be provided with
           `merge = Map(phi=2.0)`.
- `tolerance`: Relative tolerance.
- `startTime`: Start time. If value is without unit, it is assumed to have unit [s].
- `stopTime`: Stop time. If value is without unit, it is assumed to have unit [s].
- `interval`: Interval to store result. If `interval=missing`, it is internally selected as
              (stopTime-startTime)/500.
              If value is without unit, it is assumed to have unit [s].
- `interp_points`: If crossing functions defined, number of additional interpolation points
              in one step.
- `dtmax`: Maximum step size. If `dtmax==missing`, it is internally set to `100*interval`.
- `adaptive`: = true, if the `algorithm` should use step-size control (if available).
              = false, if the `algorithm` should use a fixed step-size of `interval` (if available).
- `nlinearMinForDAE`: If `algorithm` is a DAE integrator (e.g. `IDA()`) and the size of a linear equation system
              is `>= nlinearMinForDAE` and the iteration variables of this equation system are a subset of the
              DAE state derivatives, then during continuous integration (but not at events, including
              initialization) this equation system is not locally solved but is solved via the DAE integrator.
              Typically, for large linear equation systems, simulation efficiency is considerably improved
              in such a case.f
- `log`: = true, to log the simulation.
- `logStates`: = true, to log the states, its init/start values and its units.
- `logEvents`: = true, to log events.
- `logProgress` = true, to printout current simulation time every 5s.
- `logTiming`: = true, to log the timing with `instantiatedModel.timer` which is an instance
               of [TimerOutputs](https://github.com/KristofferC/TimerOutputs.jl).TimerOutput.
               A user function can include its timing via\\
               `TimerOutputs.@timeit instantiatedModel.timer "My Timing" <statement>`.
- `logParameters`: = true, to log parameters and init/start values defined in model.
- `logEvaluatedParameters`: = true, to log the evaluated parameter and init/start values that
                            are used for initialization and during simulation.
- `requiredFinalStates`: is not `missing`: Test with `@test` whether the ODE state vector at the
              final time instant is in agreement to vector `requiredFinalStates` with respect
              to tolerances `requiredFinalStates_rtol, requiredFinalStates_atol`. If this is not the case, print the
              final state vector (so that it can be included with copy-and-paste in the simulate!(..) call).
              If you checked that the result of the simulation is correct, use `requiredFinalStates = []` to get
              a printout of the required final states and then copy it in your test.
- `requiredFinalStates_rtol`: Relative tolerance used for `requiredFinalStates`.
- `requiredFinalStates_atol`: Absolute tolerance used for `requiredFinalStates` (see atol in `?isapprox`)
- `useRecursiveFactorizationUptoSize`: = 0: Linear equation systems A*v=b are solved with
               `RecursiveFactorization.jl` instead of the default `lu!(..)` and `ldiv!(..)`, if
               `length(v) <= useRecursiveFactorizationUptoSize`.
               According to `RecursiveFactorization.jl` docu, it is faster as `lu!(..)` with OpenBLAS,
               for `length(v) <= 500` (typically, more as a factor of two).
               Since there had been some cases where `lu!(..)!` was successful,
               but `RecursiveFactorization.jl` failed due to a singular system, the default is to use `lu!(..)!`.

# Examples

```julia
using Modia
@usingModiaPlot

# Define model
inputSignal(t) = sin(t)

FirstOrder = Model(
    T = 0.2,
    x = Var(init=0.3),
    equations = :[u = inputSignal(time/u"s"),
                  T * der(x) + x = u,
                  y = 2*x]
)

# Modify parameters and initial values of model
FirstOrder2 = FirstOrder | Map(T = 0.4, x = Var(init=0.6))

# Instantiate model
firstOrder = @instantiateModel(FirstOrder2, logCode=true)


# Simulate with automatically selected algorithm (Sundials.CVODE_BDF())
# and modified parameter and initial values
simulate!(firstOrder, stopTime = 1.0, merge = Map(T = 0.6, x = 0.9), logEvaluatedParameters=true)

# Plot variables "x", "u" in diagram 1, "der(x)" in diagram 2, both diagrams in figure 3
plot(firstOrder, [("x","u"), "der(x)"], figure=3)

# Retrieve "time" and "u" values:
usig = getPlotSignal(firstOrder, "x")
       # usig.xsig      : time vector
       # usig.xsigLegend: legend for time vector
       # usig.ysig      : "x" vector
       # usig.ysigLegend: legend for "x" vector
       # usig.ysigType  : ModiaResult.Continuous or ModiaResult.Clocked

# Simulate with Runge-Kutta 5/4 with step-size control
simulate!(firstOrder, Tsit5(), stopTime = 1.0)

# Simulate with Runge-Kutta 4 with fixed step size
simulate!(firstOrder, RK4(), stopTime = 1.0, adaptive=false)

# Simulate with algorithm that switches between
# Verners Runge-Kutta 6/5 algorithm if non-stiff region and
# Rosenbrock 4 (= A-stable method) if stiff region with step-size control
simulate!(firstOrder, AutoVern6(Rodas4()), stopTime = 1.0)
```
"""
function simulate!(m::Nothing, args...; kwargs...)
    @info "The call of simulate!(..) is ignored, since the first argument is nothing."
    @test false
    return nothing
end

function simulate!(m::SimulationModel{FloatType,TimeType}, algorithm=missing; merge=nothing, kwargs...) where {FloatType,TimeType}
    options = SimulationOptions{FloatType,TimeType}(merge; kwargs...)
    if isnothing(options)
        @test false
        return nothing
    end
    m.options   = options
    m.time      = options.startTime
    m.isInitial = true
    m.nsegment  = 1
    reinitEventHandler!(m.eventHandler, m.options.stopTime, m.options.logEvents)

    if ismissing(algorithm) && FloatType == Float64
        algorithm = Sundials.CVODE_BDF()
    end
    m.algorithmName = getAlgorithmName(algorithm)
    m.sundials      = !ismissing(algorithm) && (typeof(algorithm) <: Sundials.SundialsODEAlgorithm || typeof(algorithm) <: Sundials.SundialsDAEAlgorithm)
    m.addEventPointsDueToDEBug = m.sundials

    # Initialize/re-initialize SimulationModel
    if m.options.log || m.options.logEvaluatedParameters || m.options.logStates
        println("\n... Simulate model ", m.modelName)
    end

    useRecursiveFactorizationUptoSize = m.options.useRecursiveFactorizationUptoSize
    for leq in m.linearEquations
        leq.useRecursiveFactorization = length(leq.x) <= useRecursiveFactorizationUptoSize && length(leq.x) > 1
    end

    if m.options.log || m.options.logTiming
        @time (success = init!(m); if m.options.log || m.options.logTiming; print("      Initialization finished within") end)
    else
        success = init!(m)
    end
    if !success
        @test false
        return nothing
    end

    enable_timer!(m.timer)
    reset_timer!(m.timer)
    m.cpuLast  = time_ns()
    m.cpuFirst = m.cpuLast
    eh = m.eventHandler
    solution = nothing

    # --------------------------------------------------------- Core simulation loop ---------------------------------
    TimerOutputs.@timeit m.timer "Modia.simulate!" while true
        solution = simulateSegment!(m, algorithm; kwargs...)

        # Terminate simulation of current segment
        finalStates = solution.u[end]
        finalTime   = solution.t[end]
        #m.result_x = solution
        if m.eventHandler.restart != Modia.FullRestart
            eh.terminalOfAllSegments = true
        end
        terminate!(m, finalStates, finalTime)
        eh.terminalOfAllSegments = false

        # Raise an error, if simulation was not successful
        if !(solution.retcode == :Default || solution.retcode == :Success || solution.retcode == :Terminated)
            error("\nsolution = simulate!(", m.modelName, ", ...) failed with solution.retcode = :$(solution.retcode) at time = $finalTime.\n")
        end

        if m.eventHandler.restart != Modia.FullRestart
            break
        end

        # Re-initialize model for FullRestart

    end # --------------------------------------------------------- End of core simulation loop ------------------------------

    disable_timer!(m.timer)

    if !m.success
        return nothing
    end

    if m.options.log
        eh = m.eventHandler
        useRecursiveFactorization = Bool[leq.useRecursiveFactorization for leq in m.linearEquations]
        println("      Termination of ", m.modelName, " at time = ", solution.t[end], " s")
        println("        cpuTime (without init.)   = ", round(TimerOutputs.time(m.timer["Modia.simulate!"])*1e-9, sigdigits=3), " s")
        println("        allocated (without init.) = ", round(TimerOutputs.allocated(m.timer["Modia.simulate!"])/1048576.0, sigdigits=3), " MiB")
        println("        algorithm                 = ", get_algorithmName_for_heading(m))
        println("        FloatType                 = ", FloatType)
        println("        interval                  = ", m.options.interval, " s")
        println("        tolerance                 = ", m.options.tolerance, " (relative tolerance)")
        println("        nStates                   = ", length(m.x_start))
        println("        linearSystemSizes         = ", Int[length(leq.b) for leq in m.linearEquations])
        println("        useRecursiveFactorization = ", useRecursiveFactorization)
        println("        odeModeLinearSystems      = ", Bool[leq.odeMode for leq in m.linearEquations])
        println("        nResults                  = ", length(m.result.t[end]))
        println("        nGetDerivatives           = ", m.nGetDerivatives, " (total number of getDerivatives! calls)")
        println("        nf                        = ", m.nf, " (number of getDerivatives! calls from integrator)")  # solution.destats.nf
        println("        nZeroCrossings            = ", eh.nZeroCrossings, " (number of getDerivatives! calls for zero crossing detection)")

        if m.sundials && (eh.nTimeEvents > 0 || eh.nStateEvents > 0)
            # statistics is wrong, due to a bug in the Sundials.jl interface
            println("        nJac                      = ??? (number of Jacobian computations)")
            println("        nAcceptedSteps            = ???")
            println("        nRejectedSteps            = ???")
            println("        nErrTestFails             = ???")
        else
            println("        nJac                      = ", solution.destats.njacs, " (number of Jacobian computations)")
            println("        nAcceptedSteps            = ", solution.destats.naccept)
            println("        nRejectedSteps            = ", solution.destats.nreject)
            println("        nErrTestFails             = ", solution.destats.nreject)
        end
        println("        nTimeEvents               = ", eh.nTimeEvents)
        println("        nStateEvents              = ", eh.nStateEvents)
        if eh.nFullRestartEvents > 0
            println("        nFullRestartEvents        = ", eh.nFullRestartEvents)
        end
        println("        nRestartEvents            = ", eh.nRestartEvents)
    end
    if m.options.logTiming
        println("\n... Timings for simulation of ", m.modelName," (without initialization):")
        TimerOutputs.print_timer(TimerOutputs.flatten(m.timer), compact=true)
    end

    requiredFinalStates = m.options.requiredFinalStates
    if !ismissing(requiredFinalStates)
        finalStates = solution.u[end]
        rtol = m.options.requiredFinalStates_rtol
        atol = m.options.requiredFinalStates_atol
        if length(finalStates) != length(requiredFinalStates)
            success = false
        else
            success = isapprox(finalStates, requiredFinalStates, rtol=rtol, atol=atol)
        end

        if success
            @test success
        else
            println("\nrequiredFinalStates_rtol = $rtol")
            println("requiredFinalStates_atol = $atol")
            if length(requiredFinalStates) > 0 && typeof(requiredFinalStates[1]) <: Measurements.Measurement
                println(  "\nrequiredFinalStates   = ", measurementToString(requiredFinalStates))
                printstyled("finalStates           = ", measurementToString(finalStates), "\n\n", bold=true, color=:red)
                if length(finalStates) == length(requiredFinalStates)
                    printstyled("difference            = ", measurementToString(requiredFinalStates-finalStates), "\n\n", bold=true, color=:red)
                end
            else
                println(  "\nrequiredFinalStates   = ", requiredFinalStates)
                printstyled("finalStates           = ", finalStates, "\n\n", bold=true, color=:red)
                if length(finalStates) == length(requiredFinalStates)
                    printstyled("difference            = ", requiredFinalStates-finalStates, "\n\n", bold=true, color=:red)
                end
            end
            if length(finalStates) == length(requiredFinalStates)
                printstyled("maximum(|difference|) = ", maximum(abs.(requiredFinalStates-finalStates)), "\n\n", bold=true, color=:red)
            end
            @test isapprox(finalStates, requiredFinalStates, rtol=rtol, atol=atol)
        end
    end

    return solution

    #=
    catch e
        if isa(e, ErrorException)
            println()
            printstyled("Error during simulation at time = $(m.time) s:\n\n", bold=true, color=:red)
            printstyled(e.msg, "\n", bold=true, color=:red)
            printstyled("\nAborting simulate!(..) for model $(m.modelName) instantiated in file\n$(m.modelFile).\n", bold=true, color=:red)
            println()
            m.lastMessage = deepcopy(e.msg)
            #@test false
        elseif isa(e, InterruptException)
            println()
            m.lastMessage = "<ctrl> C interrupt during simulation at time = $(m.time) s.\n"
            printstyled(m.lastMessage, bold=true, color=:red)
            printstyled("\nAborting simulate!(..) for model $(m.modelName) instantiated in file\n$(m.modelFile).", bold=true, color=:red)
            println()
        else
            println("... in else branch")
            Base.rethrow()
        end
    end
    =#
end


function simulateSegment!(m::SimulationModel{FloatType,TimeType}, algorithm=missing; kwargs...) where {FloatType,TimeType}
    solution = nothing

    sizesOfLinearEquationSystems = Int[length(leq.b) for leq in m.linearEquations]

    # Define problem and callbacks based on algorithm and model type
    interval = m.options.interval
    if  abs(m.options.stopTime - m.options.startTime) <= 0
        interval = 1.0
        tspan2   = [m.options.startTime]
    elseif abs(m.options.interval) < abs(m.options.stopTime-m.options.startTime)
        tspan2 = m.options.startTime:m.options.interval:m.options.stopTime
    else
        tspan2 = [m.options.startTime, m.options.stopTime]
    end
    tspan = (m.options.startTime, m.options.stopTime)

    eh = m.eventHandler
    m.odeMode   = true
    m.solve_leq = true
    if typeof(algorithm) <: DifferentialEquations.DiffEqBase.AbstractDAEAlgorithm
        # DAE integrator
        m.odeIntegrator = false
        nx = length(m.x_init)
        differential_vars = eh.nz > 0 ? fill(true, nx) : nothing    # due to DifferentialEquations issue #549
        copyDerivatives!(m.der_x, m.der_x_invariant, m.der_x_segment)
        TimerOutputs.@timeit m.timer "DifferentialEquations.DAEProblem" problem = DifferentialEquations.DAEProblem{true}(DAEresidualsForODE!, m.der_x, m.x_init, tspan, m, differential_vars = differential_vars)
        empty!(m.daeCopyInfo)
        if length(sizesOfLinearEquationSystems) > 0 && maximum(sizesOfLinearEquationSystems) >= options.nlinearMinForDAE
            # Prepare data structure to efficiently perform copy operations for DAE integrator
            x_info      = m.equationInfo.x_info
            der_x_dict  = m.equationInfo.der_x_dict
            der_x_names = keys(der_x_dict)
            for (ileq,leq) in enumerate(m.linearEquations)
                if sizesOfLinearEquationSystems[ileq] >= options.nlinearMinForDAE &&
                   length(intersect(leq.x_names,der_x_names)) == length(leq.x_names)
                    # Linear equation shall be solved by DAE and all unknowns of the linear equation system are DAE derivatives
                    leq.odeMode = false
                    m.odeMode   = false
                    leq_copy = LinearEquationsCopyInfoForDAEMode(ileq)
                    for ix in 1:length(leq.x_names)
                        x_name   = leq.x_names[ix]
                        x_length = leq.x_lengths[ix]
                        x_info_i = x_info[ der_x_dict[x_name] ]
                        @assert(x_length == x_info_i.length)
                        startIndex = x_info_i.startIndex
                        endIndex   = startIndex + x_length - 1
                        append!(leq_copy.index, startIndex:endIndex)
                    end
                    push!(m.daeCopyInfo, leq_copy)
                else
                    leq.odeMode = true
                end
            end
        end
    else
        # ODE integrator
        m.odeIntegrator = true
        TimerOutputs.@timeit m.timer "DifferentialEquations.ODEProblem" problem = DifferentialEquations.ODEProblem{true}(derivatives!, m.x_init, tspan, m)
    end

    callback2 = DifferentialEquations.DiscreteCallback(timeEventCondition!, affectTimeEvent!)
    if eh.nz > 0
        #println("\n!!! Callback set with crossing functions")
        # Due to DifferentialEquations bug https://github.com/SciML/DifferentialEquations.jl/issues/686
        # FunctionalCallingCallback(outputs!, ...) is not correctly called when zero crossings are present.
        # The fix is to call outputs!(..) from the previous to the current event, when an event occurs.
        # (alternativey: callback4 = DifferentialEquations.PresetTimeCallback(tspan2, affect_outputs!) )
        callback1 = DifferentialEquations.FunctionCallingCallback(outputs!, funcat=[m.options.startTime]) # call outputs!(..) at startTime
        callback3 = DifferentialEquations.VectorContinuousCallback(zeroCrossings!,
                        affectStateEvent!, eh.nz, interp_points=m.options.interp_points, rootfind=DifferentialEquations.SciMLBase.RightRootFind)
        #callback4 = DifferentialEquations.PresetTimeCallback(tspan2, affect_outputs!)
        callbacks = DifferentialEquations.CallbackSet(callback1, callback2, callback3)   #, callback4)
    else
        #println("\n!!! Callback set without crossing functions")
        callback1 = DifferentialEquations.FunctionCallingCallback(outputs!, funcat=tspan2)
        callbacks = DifferentialEquations.CallbackSet(callback1, callback2)
    end

    # Initial step size (the default of DifferentialEquations integrators is too large) + step-size of fixed-step algorithm
    if !m.sundials
        dt = m.options.adaptive ? m.options.interval/10 : m.options.interval   # initial step-size
    end

    # Compute solution
    abstol = 0.1*m.options.tolerance
    tstops = (m.eventHandler.nextEventTime,)
    maxiters = Int(typemax(Int32))  # switch off maximum number of iterations (typemax(Int) gives an inexact error for Sundials)
    if ismissing(algorithm)
        TimerOutputs.@timeit m.timer "DifferentialEquations.solve" solution = DifferentialEquations.solve(problem, reltol=m.options.tolerance, abstol=abstol, save_everystep=false,
                                                                        callback=callbacks, adaptive=m.options.adaptive, saveat=tspan2, dt=dt, dtmax=m.options.dtmax, maxiters=maxiters, tstops = tstops,
                                                                        initializealg = DifferentialEquations.NoInit())
    elseif m.sundials
        TimerOutputs.@timeit m.timer "DifferentialEquations.solve" solution = DifferentialEquations.solve(problem, algorithm, reltol=m.options.tolerance, abstol=abstol, save_everystep=false,
                                                                        callback=callbacks, adaptive=m.options.adaptive, saveat=tspan2, dtmax=m.options.dtmax, maxiters=maxiters, tstops = tstops,
                                                                        initializealg = DifferentialEquations.NoInit())
    else
        TimerOutputs.@timeit m.timer "DifferentialEquations.solve" solution = DifferentialEquations.solve(problem, algorithm, reltol=m.options.tolerance, abstol=abstol, save_everystep=false,
                                                                        callback=callbacks, adaptive=m.options.adaptive, saveat=tspan2, dt=dt, dtmax=m.options.dtmax, maxiters=maxiters, tstops = tstops,
                                                                        initializealg = DifferentialEquations.NoInit())
    end

    # Compute and store outputs from last event until final time
    sol_t = solution.t
    sol_x = solution.u
    m.storeResult = true
#   for i = length(m.result_code)+1:length(sol_t)
    for i = length(m.result.t[end])+1:length(sol_t)
        invokelatest_getDerivatives_without_der_x!(sol_x[i], m, sol_t[i])
    end
    m.storeResult = false

    if ismissing(algorithm)
        m.algorithmName = getAlgorithmName(solution.alg)
    end

    return solution
end


#---------------------------------------------------------------------
#                          Linearization
#---------------------------------------------------------------------

"""
    (A, finalStates) = linearize!(instantiatedModel [, algorithm];
                                  stopTime = 0.0,
                                  analytic = false,
                                  <all other keyword arguments of simulate!>)

Simulate until `stopTime` and linearize `instantiatedModel` at `finalStates`.
The names of the state vector can be inquired by `get_xNames(instantiatedModel)`.

By default, linearization is performed numerically with a central finite difference
approximation using package [FiniteDiff](https://github.com/JuliaDiff/FiniteDiff.jl).
When setting `analytic = true`, linearization is preformed analytically with package
[ForwardDiff](https://github.com/JuliaDiff/ForwardDiff.jl),
so is computed by symbolically differentiating the model.
`ForwardDiff` might not be compatible with some floating point types, such as
`Measurements` and Julia triggers an error that some overloaded
operations are ambiguous. So `analytic=true` will not work in such cases.

Analytic linearization returns matrix `A` in full precision whereas numeric linearization
returns `A` in reduced precision (if FloatType = Float64, analytic linearization results in about
15 correct digits and numeric linearization in about 10 correct digits in the result).
You can improve this situation, by using a larger
`FloatType` for `instantiatedModel`, in case this is critical (see example below).

# Output arguments

- `A::Matrix`: Matrix A of the linear ODE: ``\\Delta \\dot{x} = A*\\Delta x``.

- `finalStates::Vector`: Linearization point.


# Example

```julia
using Modia
using DoubleFloats
using Measurements

FirstOrder = Model(
    T = 0.4 ± 0.04,
    x = Var(init = 0.9 ± 0.09),
    equations = :[u = inputSignal(time/u"s"),
                  T * der(x) + x = u]
)

firstOrder1 = @instantiateModel(FirstOrder, FloatType = Measurement{Float64})

# Standard precision
(A1, finalStates1) = linearize!(firstOrder1)

# Higher precision
firstOrder2 = SimulationModel{Measurement{Double64}}(firstOrder1)
(A2, finalStates2) = linearize!(firstOrder2)

# Show results with 15 digits (default print with Measurements shows 3 digits)
println(IOContext(stdout, :error_digits=>15), "A1 = ", A1)
println(IOContext(stdout, :error_digits=>15), "A2 = ", A2)
```
"""
function linearize!(m::Nothing, args...; kwargs...)
    @info "The call of linearize!(..) is ignored, since the first argument is nothing."
    return   nothing
end

function linearize!(m::SimulationModel{FloatType,TimeType}, algorithm=missing;
                    merge = nothing, stopTime = 0.0, analytic = false, kwargs...) where {FloatType,TimeType}
    if analytic
        @info "linearize!(.., analytic=true) of model $(m.modelName) \nis modified to analytic=false, because analytic=true is currently not supported!"
        analytic = false
    end

    solution = simulate!(m, algorithm; merge=merge, stopTime=stopTime, kwargs...)
    finalStates = solution[:,end]

    # Function that shall be linearized
    function modelToLinearize!(der_x, x)
        derivatives!(der_x, x, m, m.options.startTime)
        return nothing
    end

    # Linearize
    if analytic
        der_x = zeros(FloatType, length(finalStates))
        A = ForwardDiff.jacobian(modelToLinearize!, der_x, finalStates)
    else
        A = zeros(FloatType, length(finalStates), length(finalStates))
        FiniteDiff.finite_difference_jacobian!(A, modelToLinearize!, finalStates)
    end

    return (A, finalStates)
end


#------------------------------------------------------------------------------------------------
#        Provide the overloaded ModiaResult Abstract Interface for the results of SimulationModel
#------------------------------------------------------------------------------------------------

ModiaResult.timeSignalName(  m::SimulationModel) = m.result.timeName
ModiaResult.hasOneTimeSignal(m::SimulationModel) = length(m.result.t) == 1


"""
    hasSignal(instantiatedModel::Modia.SimulationModel, name::AbstractString)

Return true if time-varying variable `name` (for example `name = "a.b.c"`)
is defined in the instantiateModel that can be accessed and can be used for plotting.
"""
ModiaResult.hasSignal(m::SimulationModel, name::AbstractString) = begin
    if isnothing(m) || ismissing(m) || ismissing(m.result)
        return false
    end
    haskey(m.result.info, name) || !ismissing(get_value(m.evaluatedParameters, name))
end


"""
    hasParameter(instantiatedModel, name::AbstractString)

Return true if parameter `name` (for example `name = "a.b.c"`)
is defined in the instantiateModel.
"""
hasParameter(m::SimulationModel, name::AbstractString) = begin
    if isnothing(m) || ismissing(m) || ismissing(m.result)
        return false
    end
    !ismissing(get_value(m.evaluatedParameters, name))
end


"""
    getParameter(instantiatedModel, name::AbstractString)

Return the value of parameter or init/start value `name` (for example `name = "a.b.c"`).
If `name` is not known, `missing` is returned.
"""
getParameter(m::SimulationModel, name::AbstractString) = get_value(m.parameters, name)


"""
    getEvaluatedParameter(instantiatedModel, name::AbstractString)

Return the value of evaluated parameter or init/start value `name` (for example `name = "a.b.c"`).
If `name` is not known, `missing` is returned.
"""
getEvaluatedParameter(m::SimulationModel, name::AbstractString) = get_value(m.evaluatedParameters, name)


"""
    showParameters(instantiatedModel)

Print the parameters and the init/start values.
"""
function showParameters(m::SimulationModel)::Nothing
    parameters = m.parameters
    @showModel parameters
    return nothing
end


"""
    showEvaluatedParameters(instantiatedModel)

Print the evaluated parameters and the evaluated init/start values.
"""
function showEvaluatedParameters(m::SimulationModel)::Nothing
    evaluatedParameters = m.evaluatedParameters
    @showModel evaluatedParameters
    return nothing
end


"""
    names = signalNames(instantiatedModel::Modia.SimulationModel)

Return the names of the time-varying variables of an
[`@instantiateModel`](@ref) that are present in the result (e.g. can be accessed for plotting).
"""
ModiaResult.signalNames(m::SimulationModel) = collect(keys(m.result.info))


#=
import ChainRules

function ChainRules.rrule(::typeof(ResultView), v, i)
    y = ResultView(v,i)

    function ResultView_pullback(ȳ)
        return ChainRules.NO_FIELDS, collect(y)...
    end

    return y, ResultView_pullback
end
=#

"""
    (timeSignal, signal, signalType) = ModiaResult.rawSignal(instantiatedModel, name)
    (timeSignal, signal, signalType) = Modia.rawSignal(      instantiatedModel, name)

Get raw signal of result from an instantiated model of Modia.
"""
function ModiaResult.rawSignal(m::SimulationModel, name::AbstractString)
    if haskey(m.result.info, name)
        return rawSignal(m.result, name, unitless=m.unitless)
    else
        value = get_value(m.evaluatedParameters, name)
        if ismissing(value)
            error("rawSignal: \"$name\" not in result and not a parameter of model $(m.modelName))")
        end
        signal = [ ModiaResult.OneValueVector(value, length(tk)) for tk in m.result.t ]
        return (m.result.t, signal, ModiaResult.Continuous)
    end
#=
    tsig = m.result_x.t
    if !m.unitless
        tsig = tsig*u"s"
        if !(m.options.desiredResultTimeUnit == NoUnits ||
            m.options.desiredResultTimeUnit == u"s")
            tsig = uconvert.(m.options.desiredResultTimeUnit, tsig)
        end
    end

    if name == "time"
        return ([tsig], [tsig], ModiaResult.Independent)
    end

    if haskey(m.result_info, name)
        #println("rawSignal: name = $name")
        resInfo = m.result_info[name]

        if resInfo.store == RESULT_X
            (ibeg,iend,xunit) = get_xinfo(m, resInfo.index)
            if ibeg == iend
                xSig = [v[ibeg] for v in m.result_x.u]
            else
                xSig = [v[ibeg:iend] for v in m.result_x.u]
            end
            if resInfo.negate
                xSig *= -1
            end
            if !m.unitless && xunit != ""
                xSig = xSig*uparse(xunit)
            end
            return ([tsig], [xSig], ModiaResult.Continuous)

        elseif resInfo.store == RESULT_DER_X
            (ibeg,iend,xunit) = get_xinfo(m, resInfo.index)
            if ibeg == iend
                derxSig = [v[ibeg] for v in m.result_der_x]
            else
                derxSig = [v[ibeg:iend] for v in m.result_der_x]
            end
            if resInfo.negate
                derxSig *= -1
            end

            if !m.unitless
                if xunit == ""
                    derxSig = derxSig/u"s"
                else
                    derxSig = derxSig*(uparse(xunit)/u"s")
                end
            end
            return ([tsig], [derxSig], ModiaResult.Continuous)

        elseif resInfo.store == RESULT_CODE
            signal = ModiaResult.SignalView(m.result_code, resInfo.index, resInfo.negate)
            if length(signal) != length(tsig)
                lens = length(signal)
                lent = length(tsig)
                error("Bug in SimulateAndPlot.jl (rawSignal(..)): name=\"$name\",\nlength(signal) = $lens, length(tsig) = $lent")
            end
            return ([tsig], [signal], ModiaResult.Continuous)

        elseif resInfo.store == RESULT_EXTRA
            signal = ModiaResult.SignalView(m.result_extra, resInfo.index, resInfo.negate)
            if length(signal) != length(tsig)
                lens = length(signal)
                lent = length(tsig)
                error("Bug in SimulateAndPlot.jl (rawSignal(..)): name=\"$name\",\nlength(signal) = $lens, length(tsig) = $lent")
            end
            return ([tsig], [signal], ModiaResult.Continuous)

        elseif resInfo.store == RESULT_ZERO
            signal = ModiaResult.OneValueVector(0.0, length(tsig))
            return ([tsig], [signal], ModiaResult.Continuous)

        else
            error("Bug in SimulateAndPlot.jl (rawSignal(..)): name=\"$name\", resInfo=$resInfo")
        end
    end
=#
end




"""
    leaveName = get_leaveName(pathName::String)

Return the `leaveName` of `pathName`.
"""
get_leaveName(pathName::String) =
    begin
        j = findlast('.', pathName);
        typeof(j) == Nothing || j >= length(pathName) ? pathName : pathName[j+1:end]
    end


function get_algorithmName_for_heading(m::SimulationModel)::String
    if ismissing(m.algorithmName)
        algorithmName = "???"
    else
        algorithmName = m.algorithmName
        i1 = findfirst("CompositeAlgorithm", algorithmName)
        if !isnothing(i1)
            i2 = findfirst("Vern" , algorithmName)
            i3 = findfirst("Rodas", algorithmName)
            success = false
            if !isnothing(i2) && !isnothing(i3)
                i2b = findnext(',', algorithmName, i2[1])
                i3b = findnext('{', algorithmName, i3[1])
                if !isnothing(i2b) && !isnothing(i3b)
                    algorithmName = algorithmName[i2[1]:i2b[1]-1] * "(" * algorithmName[i3[1]:i3b[1]-1] * "())"
                    success = true
                end
            end
            if !success
                algorithmName = "CompositeAlgorithm"
            end
        else
            i1 = findfirst('{', algorithmName)
            if !isnothing(i1)
                algorithmName = algorithmName[1:i1-1]
            end
            i1 = findlast('.', algorithmName)
            if !isnothing(i1)
                algorithmName = algorithmName[i1+1:end]
            end
        end
    end
    return algorithmName
end


function ModiaResult.defaultHeading(m::SimulationModel)
    FloatType = get_leaveName( string( typeof( m.x_start[1] ) ) )

    algorithmName = get_algorithmName_for_heading(m)
    if FloatType == "Float64"
        heading = m.modelName * " (" * algorithmName * ")"
    else
        heading = m.modelName * " (" * algorithmName * ", " * FloatType * ")"
    end
    return heading
end



# For backwards compatibility

"""
    signal    = get_result(instantiatedModel, name; unit=true)
    dataFrame = get_result(instantiatedModel; onlyStates=false, extraNames=missing)

- First form: After a successful simulation of `instantiatedModel`, return
  the result for the signal `name::String` as vector of points
  together with its unit. The time vector has path name `"time"`.
  If `unit=false`, the signal is returned, **without unit**.

- Second form: Return the **complete result** in form of a DataFrame object.
  Therefore, the whole functionality of package [DataFrames](https://dataframes.juliadata.org/stable/)
  can be used, including storing the result on file in different formats.
  Furthermore, also plot can be used on dataFrame.
  Parameters and zero-value variables are stored as ModiaResult.OneValueVector inside dataFrame
  (are treated as vectors, but actually only the value and the number
  of time points is stored). If `onlyStates=true`, then only the states and the signals
  identified with `extraNames::Vector{String}` are stored in `dataFrame`.
  If `onlyStates=false` and `extraNames` given, then only the signals
  identified with `extraNames` are stored in `dataFrame`.
  These keyword arguments are useful, if `dataFrame` shall be
  utilized as reference result used in compareResults(..).

In both cases, a **view** on the internal result memory is provided
(so result data is not copied).

# Example

```julia
using Modia
@usingModiaPlot
using Unitful

include("\$(Modia.path)/examples/Pendulum.jl")
using  .Model_Pendulum

pendulum = simulationModel(Pendulum)
simulate!(pendulum, stopTime=7.0)

# Get one signal from the result and plot with the desired plot package
time = get_result(pendulum, "time")  # vector with unit u"s"
phi  = get_result(pendulum, "phi")   # vector with unit u"rad"

import PyPlot
PyPlot.figure(4)   # Change to figure 4 (or create it, if it does not exist)
PyPlot.clf()       # Clear current figure
PyPlot.plot(stripUnit(time), stripUnit(phi), "b--", label="phi in " * string(unit(phi[1])))
PyPlot.xlabel("time in " * string(unit(time[1])))
PyPlot.legend()

# Get complete result and plot one signal
result = get_result(pendulum)
plot(result, "phi")

# Get only states to be used as reference and compare result with reference
reference = get_result(pendulum, onlyStates=true)
(success, diff, diff_names, max_error, within_tolerance) =
    ModiaResult.compareResults(result, reference, tolerance=0.01)
println("Check results: success = $success")
```
"""
function get_result(m::SimulationModel, name::AbstractString; unit=true)
    #(xsig, xsigLegend, ysig, ysigLegend, yIsConstant) = ModiaResult.getPlotSignal(m, "time", name)

    #resIndex = m.variables[name]
    #ysig = ResultView(m.result, abs(resIndex), resIndex < 0)

    #if ModiaResult.timeSignalName(m) != 1
    if length(m.result.t) > 1
        error("Error in Modia.get_result(\"$name\"), because function cannot be used for a segmented simulation with more as one segment.")
    end

    (tsig2, ysig2, ysigType) = ModiaResult.rawSignal(m, name)
    ysig = ysig2[1]
    ysig = unit ? ysig : stripUnit.(ysig)

    #=
    if yIsConstant
        if ndims(ysig) == 1
            ysig = fill(ysig[1], length(xsig))
        else
            ysig = fill(ysig[1,:], length(xsig))
        end
    end
    =#

    return ysig
end


function setEvaluatedParametersInDataFrame!(obj::OrderedDict{Symbol,Any}, result_info, dataFrame::DataFrames.DataFrame, path::String, nResult::Int)::Nothing
    for (key,value) in zip(keys(obj), obj)
        name = appendName(path, key)
        if typeof(value) <: OrderedDict{Symbol,Any}
            setEvaluatedParametersInDataFrame!(value, result_info, dataFrame, name, nResult)
        elseif !haskey(result_info, name)
            dataFrame[!,name] = ModiaResult.OneValueVector(value,nResult)
        end
    end
    return nothing
end


function get_result(m::SimulationModel; onlyStates=false, extraNames=missing)
    if length(m.result.t) > 1
        error("Error in Modia.get_result(...), because function cannot be used for a segmented simulation with more as one segment.")
    end

    dataFrame = DataFrames.DataFrame()

    (timeSignal, signal, signalType) = ModiaResult.rawSignal(m, "time")
    dataFrame[!,"time"] = timeSignal[1]

    if onlyStates || !ismissing(extraNames)
        if onlyStates
            for name in keys(m.equationInfo.x_dict)
                (timeSignal, signal, signalType) = ModiaResult.rawSignal(m, name)
                dataFrame[!,name] = signal[1]
            end
        end
        if !ismissing(extraNames)
            for name in extraNames
                (timeSignal, signal, signalType) = ModiaResult.rawSignal(m, name)
                dataFrame[!,name] = signal[1]
            end
        end

    else
        for name in keys(m.result.info)
            if name != "time"
                (timeSignal, signal, signalType) = ModiaResult.rawSignal(m, name)
                dataFrame[!,name] = signal[1]
            end
        end

        setEvaluatedParametersInDataFrame!(m.evaluatedParameters, m.result.info, dataFrame, "", length(timeSignal[1]))
    end
    return dataFrame
end