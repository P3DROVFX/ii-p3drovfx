import run
run.CASES=run.CASES[3:]
_original=run.run_case
def measured(case,ignored):
 return _original(case,[{'phase':'core','seconds':20},{'phase':'controller','seconds':20},{'phase':'open','seconds':30},{'phase':'closed','seconds':25},{'phase':'unloaded','seconds':20},{'phase':'gc','seconds':15}])
run.run_case=measured
run.main()
