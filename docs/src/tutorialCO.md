# CO-oxydation (codim 2)

In this tutorial, we study the Bykov–Yablonskii–Kim
model of CO-oxydation (see [^Govaerts]). The goal of the tutorial is to show in a simple example how to perform codimension 2 bifurcation detection.

$$\left\{\begin{array}{l}\dot{x}=2 q_{1} z^{2}-2 q_{5} x^{2}-q_{3} x y \\ \dot{y}=q_{2} z-q_{6} y-q_{3} x y \\ \dot{s}=q_{4} z-k q_{4} s\end{array}\right.\tag{E}$$
Where $z=1-x-y-s$.


We start with some imports that are useful in the following.

```julia
using Revise, ForwardDiff, Parameters, Setfield, Plots, LinearAlgebra
using BifurcationKit
const BK = BifurcationKit

# define the sup norm
norminf = x -> norm(x, Inf)
```

## Problem setting

We can now encode the vector field (E) in a function and use automatic differentiation to compute its various derivatives.

```julia
# vector field of the problem
function COm(u, p)
	@unpack q1,q2,q3,q4,q5,q6,k = p
	x, y, s = u
	z = 1-x-y-s
	out = similar(u)
	out[1] = 2q1 * z^2 - 2q5 * x^2 - q3 * x * y
	out[2] = q2 * z - q6 * y - q3 * x * y
	out[3] = q4 * z - k * q4 * s
	out
end
dCOm = (z, p) -> ForwardDiff.jacobian(x -> COm(x, p), z)

# we group the differentials together
jet = BK.get3Jet(COm, dCOm)

# parameters used in the model
par_com = (q1 = 2.5, q2 = 0.6, q3 = 10., q4 = 0.0675, q5 = 1., q6 = 0.1, k = 0.4)

# initial condition
z0 = [0.07,0.2,05]
```

## Continuation

Once the problem is set up, we can continue the state and detect codim bifurcations. This is achieved as follows:

```julia
opts_br = ContinuationPar(pMin = 0.6, pMax = 1.9, ds = 0.002, dsmax = 0.01, nInversion = 6, 
	detectBifurcation = 3, maxBisectionSteps = 25, nev = 3, maxSteps = 20000)
br, = @time continuation(jet[1], jet[2], z0, par_com, (@lens _.q2), opts_br;
	printSolution = (x, p) -> (x = x[1], y = x[2]),
	plot = true, verbosity = 3, normC = norminf)
	
plot(br, xlims=(0.8,1.8))
```

And you should get:

![](com-fig1.png)

## Continuation of Fold points

We follow the Fold points in the parameter plane $(q_2, k)$. We tell the solver to consider `br.specialpoint[2]` and continue it. 

```julia
sn_codim2, = continuation(jet[1:2]..., br, 2, (@lens _.k),
	ContinuationPar(opts_br, pMax = 2.2, pMin = 0., detectBifurcation = 0, 
		ds = -0.001, dsmax = 0.05);
	normC = norminf,
	# we save the first component for plotting
	printSolution = (u,p; kw...) -> (x = u.u[1] ),
	# we update the Fold problem at every continuation step
	updateMinAugEveryStep = 1,
	# compute both sides of the initial condition
	bothside=true,
	# use this linear bordered solver, better for ODEs
	bdlinsolver = MatrixBLS())
	
plot(sn_codim2, vars=(:q2, :x), branchlabel = "Fold")
plot!(br, xlims=(0.8,1.8))
```

![](com-fig2.png)

## Continuation of Hopf points

We tell the solver to consider `br.bifpint[1]` and continue it. 

```julia
hp_codim2, = continuation(jet[1:2]..., br, 1, (@lens _.k), 
	ContinuationPar(opts_br, pMin = 0., pMax = 2.8, detectBifurcation = 0, 
		ds = -0.001, dsmax = 0.1) ; normC = norminf,
	# tell to start the Hopf problem using eigen elements: compute left eigenvector
	startWithEigen = true,
	# we save the first component for plotting
	printSolution = (u,p; kw...) -> (x = u.u[1] ),
	# we update the Hopf problem at every continuation step
	updateMinAugEveryStep = 1,
	# compute both sides of the initial condition
	bothside = true,
	# use this linear bordered solver, better for ODEs
	bdlinsolver = MatrixBLS(),
	)
	
# plotting
plot(sn_codim2, vars=(:q2, :x), branchlabel = "Fold")
plot!(hp_codim2, vars=(:q2, :x), branchlabel = "Hopf")
plot!(br, xlims=(0.6,1.5))
```	

![](com-fig3.png)

## References

[^Govaerts]: > Govaerts, Willy J. F. Numerical Methods for Bifurcations of Dynamical Equilibria. Philadelphia, Pa: Society for Industrial and Applied Mathematics, 2000.
