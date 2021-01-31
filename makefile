all: cudbg_test

cudbg_test: cudbg_test.cu
	nvcc -I/opt/cuda/extras/Debugger/include $< -o $@ -lcuda

clean:
	rm -rf cudbg_test

