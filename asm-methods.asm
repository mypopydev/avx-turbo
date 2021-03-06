BITS 64
default rel

%if (__NASM_MAJOR__ < 2) || (__NASM_MINOR__ < 11)
%deftok ver __NASM_VER__
%error Your nasm version (ver) is too old, you need at least 2.11 to compile this
%endif

%include "nasm-utils-inc.asm"

nasm_util_assert_boilerplate
thunk_boilerplate

; aligns and declares the global label for the bench with the given name
; also potentally checks the ABI compliance (if enabled)
%macro define_func 1
abi_checked_function %1
%endmacro

; define a test func that unrolls the loop by 100
; with the given body instruction
; %1 - function name
; %2 - init instruction (e.g., xor out the variable you'll add to)
; %3 - loop body instruction
%macro test_func 3
define_func %1
%2
.top:
times 100 %3
sub rdi, 100
jnz .top
ret
%endmacro

test_func scalar_iadd,    {xor eax, eax}, {add rax, rax}
test_func avx128_iadd,    {vpcmpeqd xmm0, xmm0, xmm0}, {vpaddq  xmm0, xmm0, xmm0}
test_func avx128_iadd_t,  {vpcmpeqd xmm1, xmm0, xmm0}, {vpaddq  xmm0, xmm1, xmm1}
test_func avx128_imul,    {vpcmpeqd xmm0, xmm0, xmm0}, {vpmuldq xmm0, xmm0, xmm0}
test_func avx128_fma ,    {vpxor    xmm0, xmm0, xmm0}, {vfmadd132pd xmm0, xmm0, xmm0}
test_func avx256_iadd,    {vpcmpeqd ymm0, ymm0, ymm0}, {vpaddq  ymm0, ymm0, ymm0}
test_func avx256_iadd_t,  {vpcmpeqd ymm1, ymm0, ymm0}, {vpaddq  ymm0, ymm1, ymm1}
test_func avx256_imul,    {vpcmpeqd ymm0, ymm0, ymm0}, {vpmuldq ymm0, ymm0, ymm0}
test_func avx256_fma ,    {vpxor    xmm0, xmm0, xmm0}, {vfmadd132pd ymm0, ymm0, ymm0}
test_func avx512_iadd,    {vpcmpeqd ymm0, ymm0, ymm0}, {vpaddq  zmm0, zmm0, zmm0}
test_func avx512_imul,    {vpcmpeqd ymm0, ymm0, ymm0}, {vpmuldq zmm0, zmm0, zmm0}
test_func avx512_vpermw,  {vpcmpeqd ymm0, ymm0, ymm0}, {vpermw  zmm0, zmm0, zmm0}
test_func avx512_vpermd,  {vpcmpeqd ymm0, ymm0, ymm0}, {vpermd  zmm0, zmm0, zmm0}
test_func avx512_fma ,    {vpxor    xmm0, xmm0, xmm0}, {vfmadd132pd zmm0, zmm0, zmm0}

; this is like test_func, but it uses 10 parallel chains of instructions,
; unrolled 10 times, so (probably) max throughput
; %1 - function name
; %2 - init instruction (e.g., xor out the variable you'll add to)
; %3 - register base like xmm, ymm, zmm
; %3 - loop body instruction only (no operands)
%macro test_func_tput 5
define_func %1

; init
%assign r 0
%rep 10
%2 %3 %+ r, %5
%assign r (r+1)
%endrep

.top:
%rep 10
%assign r 0
%rep 10
%4 %3 %+ r, %3 %+ r, %3 %+ r
%assign r (r+1)
%endrep
%endrep
sub rdi, 100
jnz .top
ret
%endmacro

test_func_tput avx128_fma_t ,   vmovddup,     xmm, vfmadd132pd, [zero_dp]
test_func_tput avx256_fma_t ,   vbroadcastsd, ymm, vfmadd132pd, [zero_dp]
test_func_tput avx512_fma_t ,   vbroadcastsd, zmm, vfmadd132pd, [zero_dp]
test_func_tput avx512_vpermw_t ,vbroadcastsd, zmm, vpermw,      [zero_dp]
test_func_tput avx512_vpermd_t ,vbroadcastsd, zmm, vpermd,      [zero_dp]

; this is like test_func except that the 100x unrolled loop instruction is
; always a serial scalar add, while the passed instruction to test is only
; executed once per loop (so at a ratio of 1:100 for the scalar adds). This
; test the effect of an "occasional" AVX instruction.
; %1 - function name
; %2 - init instruction (e.g., xor out the variable you'll add to)
; %3 - loop body instruction
%macro test_func_sparse 4
define_func %1
%2
%4
xor eax, eax
.top:
%3
times 100 add eax, eax
sub rdi, 100
jnz .top
ret
%endmacro

test_func_sparse avx128_mov_sparse,       {vbroadcastsd ymm0, [one_dp]}, {vmovdqa xmm0, xmm0}, {}
test_func_sparse avx256_mov_sparse,       {vbroadcastsd ymm0, [one_dp]}, {vmovdqa ymm0, ymm0}, {}
test_func_sparse avx512_mov_sparse,       {vbroadcastsd zmm0, [one_dp]}, {vmovdqa32 zmm0, zmm0}, {}
test_func_sparse avx128_merge_sparse, {vbroadcastsd ymm0, [one_dp]}, {vmovdqa32 xmm0{k1}, xmm0}, {kmovq k1, [kmask]}
test_func_sparse avx256_merge_sparse, {vbroadcastsd ymm0, [one_dp]}, {vmovdqa32 ymm0{k1}, ymm0}, {kmovq k1, [kmask]}
test_func_sparse avx512_merge_sparse, {vbroadcastsd zmm0, [one_dp]}, {vmovdqa32 zmm0{k1}, zmm0}, {kmovq k1, [kmask]}

test_func_sparse avx128_fma_sparse, {vbroadcastsd ymm0, [zero_dp]}, {vfmadd132pd xmm0, xmm0, xmm0 }, {}
test_func_sparse avx256_fma_sparse, {vbroadcastsd ymm0, [zero_dp]}, {vfmadd132pd ymm0, ymm0, ymm0 }, {}
test_func_sparse avx512_fma_sparse, {vbroadcastsd zmm0, [zero_dp]}, {vfmadd132pd zmm0, zmm0, zmm0 }, {}


define_func ucomis
vzeroupper
;vbroadcastsd zmm15, [zero_dp]
vpxord zmm15, zmm16, zmm16
movdqu xmm0, [one_dp]
movdqu xmm2, [one_dp]
movdqu xmm1, [zero_dp]
.top:
%rep 100
addsd   xmm0, xmm2
ucomisd xmm1, xmm0
ja .never    
%endrep
sub rdi, 100
jnz .top
ret
.never:
ud2

define_func ucomis_vex
vzeroupper
vpxord zmm15, zmm16, zmm16
movdqu xmm0, [one_dp]
movdqu xmm2, [one_dp]
movdqu xmm1, [zero_dp]
.top:
%rep 100
vaddpd   xmm0, xmm0, xmm2
%endrep
sub rdi, 100
jnz .top
ret
.never:
ud2



GLOBAL zeroupper:function
zeroupper:
vzeroupper
ret

zero_dp: dq 0.0
one_dp:  dq 1.0
kmask:   dq 0x5555555555555555



