using DiffEqBase

####################################################################################################
# this function takes into accound a parameter passed to the vector field
# Putting the options `save_start=false` seems to bug with Sundials
function flowTimeSol(x, p, tm, pb::ODEProblem; alg = Euler(), kwargs...)
	_prob = DiffEqBase.remake(pb; u0 = x, tspan = (zero(tm), tm), p = p)
	# the use of concrete_solve makes it compatible with Zygote
	sol = DiffEqBase.concrete_solve(_prob, alg; save_everystep = false, kwargs...)
	return (t = sol.t[end], u = sol[end])
end

# this function is a bit different from the previous one as it is geared towards parallel computing of the flow.
function flowTimeSol(x::AbstractMatrix, p, tm, epb::EnsembleProblem; alg = Euler(), kwargs...)
	# modify the function which asigns new initial conditions
	# see docs at https://docs.sciml.ai/dev/features/ensemble/#Performing-an-Ensemble-Simulation-1
	_prob_func = (prob, ii, repeat) -> prob = remake(prob, u0 = x[:, ii], tspan = (zero(tm[ii]), tm[ii]), p = p)
	_epb = setproperties(epb, output_func = (sol,i) -> ((t = sol.t[end], u = sol[end]), false), prob_func = _prob_func)
	sol = DiffEqBase.solve(_epb, alg, EnsembleThreads(); trajectories = size(x, 2), save_everystep = false, kwargs...)
	# sol.u contains a vector of tuples (sol_i.t[end], sol_i[end])
	# @show sol.u[1]
	return sol.u
end

flow(x, p, tm, pb::ODEProblem; alg = Euler(), kwargs...) = flowTimeSol(x, p, tm, pb; alg = alg, kwargs...).u
flow(x, p, tm, pb::EnsembleProblem; alg = Euler(), kwargs...) = flowTimeSol(x, p, tm, pb; alg = alg, kwargs...)
flow(x, tm, pb::Union{ODEProblem, EnsembleProblem}; alg = Euler(), kwargs...) =  flow(x, nothing, tm, pb; alg = alg, kwargs...)
################
# function used to compute the derivative of the flow, so pb encodes the variational equation
function dflow(x::AbstractVector, dx, p, tm, pb::ODEProblem; alg = Euler(), kwargs...)
	n = length(x)
	_prob = DiffEqBase.remake(pb; u0 = vcat(x, dx), tspan = (zero(tm), tm), p = p)
	# the use of concrete_solve makes it compatible with Zygote
	sol = DiffEqBase.concrete_solve(_prob, alg, save_everystep = false; kwargs...)[end]
	return (t = tm, u = sol[1:n], du = sol[n+1:end])
end

function dflow(x::AbstractMatrix, dx, p, tm, epb::EnsembleProblem; alg = Euler(), kwargs...)
	N = size(x,1)
	_prob_func = (prob, ii, repeat) -> prob = remake(prob, u0 = vcat(x[:, ii], dx[:, ii]), tspan = (zero(tm[ii]), tm[ii]), p = p)
	_epb = setproperties(epb, output_func = (sol,i) -> ((t = sol.t[end], u = sol[end][1:N], du = sol[end][N+1:end]), false), prob_func = _prob_func)
	sol = DiffEqBase.solve(_epb, alg, EnsembleThreads(); trajectories = size(x, 2), save_everystep = false, kwargs...)
	return sol.u
end

dflow(x, dx, tspan, pb::Union{ODEProblem, EnsembleProblem}; alg = Euler(), kwargs...) = dflow(x, dx, nothing, tspan, pb; alg = alg, kwargs...)
################
# this function takes into accound a parameter passed to the vector field
function dflow_fd(x, dx, p, tm, pb::ODEProblem; alg = Euler(), δ = 1e-9, kwargs...)
	sol1 = flow(x .+ δ .* dx, p, tm, pb; alg = alg, kwargs...)
	sol2 = flow(x 			, p, tm, pb; alg = alg, kwargs...)
	return (t = tm, u = sol2, du = (sol1 .- sol2) ./ δ)
end

function dflow_fd(x, dx, p, tm, pb::EnsembleProblem; alg = Euler(), δ = 1e-9, kwargs...)
	sol1 = flow(x .+ δ .* dx, p, tm, pb; alg = alg, kwargs...)
	sol2 = flow(x 			, p, tm, pb; alg = alg, kwargs...)
	return [(t = sol1[ii][1], u = sol2[ii][2], du = (sol1[ii][2] .- sol2[ii][2]) ./ δ) for ii = 1:size(x,2) ]
end
dflow_fd(x, dx, tm, pb::Union{ODEProblem, EnsembleProblem}; alg = Euler(), δ = 1e-9, kwargs...) = (@show typeof(pb);dflow_fd(x, dx, nothing, tm, pb; alg = alg, δ = δ, kwargs...))
################
# this gives access to the full solution, convenient for Poincaré shooting
# this function takes into accound a parameter passed to the vector field and returns the full solution from the ODE solver. This is useful in Poincare Shooting to extract the period.
function flowFull(x, p, tm, pb::ODEProblem; alg = Euler(), kwargs...)
	_prob = DiffEqBase.remake(pb; u0 = x, tspan = (zero(tm), tm), p = p)
	sol = DiffEqBase.solve(_prob, alg; kwargs...)
end

function flowFull(x, p, tm, epb::EnsembleProblem; alg = Euler(), kwargs...)
	_prob_func = (prob, ii, repeat) -> prob = remake(prob, u0 = x[:, ii], tspan = (zero(tm[ii]), tm[ii]), p = p)
	_epb = setproperties(epb, output_func = (sol,i) -> ((t = sol.t, u = sol), false), prob_func = _prob_func)
	sol = DiffEqBase.solve(_epb, alg, EnsembleThreads(); trajectories = size(x, 2), kwargs...)
end
flowFull(x, tm, pb::Union{ODEProblem, EnsembleProblem}; alg = Euler(), kwargs...) = flowFull(x, nothing, tm, pb; alg = alg, kwargs...)
####################################################################################################
# Structures related to computing ODE/PDE Flows
"""
	fl = Flow(F, flow, dflow)
This composite type encapsulates:
- the vector field `x -> F(x)` associated to a Cauchy problem,
- the flow (or semigroup) associated to the Cauchy problem `(x, t) -> flow(x, t)`. Only the last time point must be returned.
- the flow (or semigroup) associated to the Cauchy problem `(x, t) -> flow(x, t)`. The whole solution on the time interval (0,t) must be returned. This is not strictly necessary to provide this.
- the differential `dflow` of the flow w.r.t. `x`, `(x, dx, t) -> dflow(x, dx, t)`. One important thing is that we require `dflow(x, dx, t)` to return a Named Tuple vectors: `(t = t, u = flow(x, t), du = dflow(x, dx, t))`, the last composant is the value of the derivative of the flow.

There are some simple constructors for which you only have to pass a `prob::ODEProblem` from `DifferentialEquations.jl` and an ODE time stepper like `Tsit5()`. Hence, you can do for example

	fl = Flow(F, prob, Tsit5(); kwargs...)

If your vector field depends on parameters `p`, you can define a `Flow` using

	fl = Flow(F, p, prob, Tsit5(); kwargs...)

Finally, you can pass two `ODEProblem` where the second one is used to compute the variational equation:

	fl = Flow(F, p, prob1::ODEProblem, alg1, prob2::ODEProblem, alg2; kwargs...)

"""
struct Flow{TF, Tf, Tts, Tff, Td, Tse}
	F::TF				# vector field F(x)
	flow::Tf			# flow(x,t)
	flowTimeSol::Tts	# flow(x,t)
	flowFull::Tff		# flow(x,t) returns full solution
	dflow::Td			# dflow(x,dx,t) returns (flow(x,t), dflow(x,t)⋅dx)
	dfserial::Tse		# serial version of flow

	function Flow(F::TF, fl::Tf, fts::Tts, flf::Tff, df::Td, fse::Tse) where {TF, Tf, Tts, Tff, Td, Tse}
		new{TF, Tf, Tts, Tff, Td, Tse}(F, fl, fts, flf, df, fse)
	end

	function Flow(F::TF, fl::Tf, df::Td) where {TF, Tf, Td}
		new{TF, Tf, Nothing, Nothing, Td, Td}(F, fl, nothing, nothing, df, df)
	end
end

(fl::Flow)(x, t)     			  = fl.flow(x, t)
(fl::Flow)(x, dx, t; kw2...) 	  = fl.dflow(x, dx, t; kw2...)
(fl::Flow)(::Val{:Full}, x, t) 	  = fl.flowFull(x, t)
(fl::Flow)(::Val{:TimeSol}, x, t) = fl.flowTimeSol(x, t)
(fl::Flow)(::Val{:Serial}, x, dx, t)  = fl.dfserial(x, dx, t)

"""
Creates a Flow variable based on a `prob::ODEProblem` and ODE solver `alg`. The vector field `F` has to be passed, this will be resolved in the future as it can be recovered from `prob`. Also, the derivative of the flow is estimated with finite differences.
"""
# this constructor takes into accound a parameter passed to the vector field
function Flow(F, p, prob::Union{ODEProblem, EnsembleProblem}, alg; kwargs...)
	probserial = prob isa EnsembleProblem ? prob.prob : prob
	return Flow(F,
		(x, t) ->			 	flow(x, p, t, prob; alg = alg, kwargs...),
		(x, t) ->		 flowTimeSol(x, p, t, prob; alg = alg, kwargs...),
		(x, t) -> 		 	flowFull(x, p, t, prob; alg = alg, kwargs...),
		# we remove the callback in order to use this for the Jacobian in Poincare Shooting
		(x, dx, t; kw2...) -> dflow_fd(x, dx, p, t, prob; alg = alg, kwargs..., kw2...),
		# serial version of dflow. Used for the computation of Floquet coefficients
		(x, dx, t; kw2...) -> dflow_fd(x, dx, p, t, probserial; alg = alg, kwargs..., kw2...)
		)
end

function Flow(F, p, prob1::Union{ODEProblem, EnsembleProblem}, alg1, prob2::Union{ODEProblem, EnsembleProblem}, alg2; kwargs...)
	probserial = prob2 isa EnsembleProblem ? prob2.prob : prob2
	return Flow(F,
		(x, t) -> 			flow(x, p, t, prob1, alg = alg1; kwargs...),
		(x, t) ->	 flowTimeSol(x, p, t, prob1; alg = alg1, kwargs...),
		(x, t) -> 		flowFull(x, p, t, prob1, alg = alg1; kwargs...),
		(x, dx, t; kw2...) ->  dflow(x, dx, p, t, prob2; alg = alg2, kwargs..., kw2...),
		# serial version of dflow. Used for the computation of Floquet coefficients
		(x, dx, t; kw2...) -> dflow(x, dx, p, t, probserial; alg = alg2, kwargs..., kw2...),
		)
end