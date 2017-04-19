test : test_redis test_client
.PHONY : test_redis

lint :
	@echo $@
	@eslint lib test
.PHONY : lint

test_redis: 
	@echo $@
	@busted test -c
	@luacov
	@tail -n +$$(($$(sed -n '/^Summary/=' luacov.report.out) - 1 )) luacov.report.out
	@echo 
.PHONY : test_redis

test_client:
	@echo $@
	@istanbul cover _mocha test
.PHONY : test_client
	
