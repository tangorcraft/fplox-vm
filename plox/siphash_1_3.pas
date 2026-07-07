unit siphash_1_3;

{$mode ObjFPC}{$H+}
{$i defines.inc}
(*
  This is translation of SipHash reference C implementation
  from [https://github.com/veorq/SipHash/blob/master/siphash.c]
  and [https://github.com/veorq/SipHash/blob/master/halfsiphash.c]
  using cROUNDS=1 and dROUNDS=3

  Revision: throwing out endianness caring and accessing data directly
*)

interface

uses
  Classes, SysUtils;

(*
    Computes a SipHash value, cROUNDS=1, dROUNDS=3
    *in: pointer to input data (read-only)
    inlen: input data length in bytes (any size_t value)
    *k: pointer to the key data (read-only), must be 16 bytes
    *out: pointer to output data (write-only), outlen bytes must be allocated
    outlen: length of the output in bytes, must be 8 or 16
*)

type
  siphash_out_length = (
    sip_out_len_8b = 8,
    sip_out_len_16b = 16
  );

procedure siphash_1_3(const data: Pointer; const data_len: SizeUInt; const K: Pointer;
  const out_buf: PByte; const out_len: siphash_out_length);

(*
    Computes a SipHash value, cROUNDS=1, dROUNDS=3
    *in: pointer to input data (read-only)
    inlen: input data length in bytes (any size_t value)
    *k: pointer to the key data (read-only), must be 8 bytes
    *out: pointer to output data (write-only), outlen bytes must be allocated
    outlen: length of the output in bytes, must be 4 or 8
*)

type
  halfsiphash_out_length = (
    half_out_len_4b = 4,
    half_out_len_8b = 8
  );

procedure halfsiphash_1_3(const data: Pointer; const data_len: SizeUInt; const K: Pointer;
  const out_buf: PByte; const out_len: halfsiphash_out_length);

implementation

{$ifdef DEBUG_SIPHASH}
uses
  common;
{$endif}

const
  V0_base = UInt64($736F6D6570736575);
  V1_base = UInt64($646F72616E646F6D);
  V2_base = UInt64($6C7967656E657261);
  V3_base = UInt64($7465646279746573);

{$inline on}

procedure siphash_1_3(const data: Pointer; const data_len: SizeUInt; const K: Pointer;
  const out_buf: PByte; const out_len: siphash_out_length);
var
  ni, ni_end: PByte;
  kk: PByte;
  v0, v1, v2, v3,
  k0, k1,
  m, b: UInt64;
  left: Integer;

  { #define ROTL(x, b) (uint64_t)(((x) << (b)) | ((x) >> (64 - (b)))) }
  procedure SIPROUND(); inline;
  begin
    v0 := v0 + v1;
    v1 := ((v1 shl 13) or (v1 shr (64-13))) //ROTL(v1, 13)
          xor v0;
    v0 := (v0 shl 32) or (v0 shr (64-32)); //ROTL(v0, 32);
    v2 := v2 + v3;
    v3 := ((v3 shl 16) or (v3 shr (64-16))) //ROTL(v3, 16)
          xor v2;
    v0 := v0 + v3;
    v3 := ((v3 shl 21) or (v3 shr (64-21))) //ROTL(v3, 21)
          xor v0;
    v2 := v2 + v1;
    v1 := ((v1 shl 17) or (v1 shr (64-17))) //ROTL(v1, 17)
          xor v2;
    v2 := (v2 shl 32) or (v2 shr (64-32)); //ROTL(v2, 32);
  end;

  {$ifdef DEBUG_SIPHASH}
  procedure TRACE(); inline;
  begin
    printf('(%3u) v0 %.16x'+NL, [data_len, v0]);
    printf('(%3u) v1 %.16x'+NL, [data_len, v1]);
    printf('(%3u) v2 %.16x'+NL, [data_len, v2]);
    printf('(%3u) v3 %.16x'+NL, [data_len, v3]);
  end;
  {$endif}

begin
  ni := data;
  kk := K;
  v0 := V0_base;
  v1 := V1_base;
  v2 := V2_base;
  v3 := V3_base;
  k0 := PUInt64(kk)^;
  k1 := PUInt64(kk + 8)^;
  ni_end := ni + (data_len - (data_len mod 8));
  left := data_len and 7;
  b := UInt64(data_len) shl 56;
  v3 := v3 xor k1;
  v2 := v2 xor k0;
  v1 := v1 xor k1;
  v0 := v0 xor k0;

  if out_len = sip_out_len_16b then
    v1 := v1 xor $ee;

  while ni <> ni_end do
  begin
    m := PUInt64(ni)^;
    v3 := v3 xor m;
    {$ifdef DEBUG_SIPHASH}TRACE();{$endif}
    SIPROUND(); // cROUNDS = 1
    v0 := v0 xor m;
    inc(ni, 8);
  end;

  m := 0;
  while left > 0 do
  begin
    dec(left);
    m := (m shl 8) or UInt64(ni[left]);
  end;
  b := b or m;

  v3 := v3 xor b;
  {$ifdef DEBUG_SIPHASH}TRACE();{$endif}
  SIPROUND(); // cROUNDS = 1
  v0 := v0 xor b;

  if out_len = sip_out_len_16b then
    v2 := v2 xor $ee
  else
    v2 := v2 xor $ff;

  {$ifdef DEBUG_SIPHASH}TRACE();{$endif}
  SIPROUND(); // dROUNDS = 3
  SIPROUND();
  SIPROUND();

  b := v0 xor v1 xor v2 xor v3;
  PUInt64(out_buf)^ := b;

  if out_len = sip_out_len_8b then
    Exit;

  v1 := v1 xor $dd;

  {$ifdef DEBUG_SIPHASH}TRACE();{$endif}
  SIPROUND(); // dROUNDS = 3
  SIPROUND();
  SIPROUND();

  b := v0 xor v1 xor v2 xor v3;
  PUInt64(out_buf + 8)^ := b;

end;

{ HalfSipHash }

const
  halfV0_base = 0;
  halfV1_base = 0;
  halfV2_base = UInt32($6c796765);
  halfV3_base = UInt32($74656462);

procedure halfsiphash_1_3(const data: Pointer; const data_len: SizeUInt; const K: Pointer;
  const out_buf: PByte; const out_len: halfsiphash_out_length);
var
  ni, ni_end: PByte;
  kk: PByte;
  v0, v1, v2, v3,
  k0, k1,
  m, b: UInt32;
  left: Integer;

  { #define ROTL(x, b) (uint32_t)(((x) << (b)) | ((x) >> (32 - (b)))) }
  procedure SIPROUND(); inline;
  begin
    v0 := v0 + v1;
    v1 := ((v1 shl 5) or (v1 shr (32-5))) //ROTL(v1, 5)
          xor v0;
    v0 := (v0 shl 16) or (v0 shr (32-16)); //ROTL(v0, 16);
    v2 := v2 + v3;
    v3 := ((v3 shl 8) or (v3 shr (32-8))) //ROTL(v3, 8)
          xor v2;
    v0 := v0 + v3;
    v3 := ((v3 shl 7) or (v3 shr (32-7))) //ROTL(v3, 7)
          xor v0;
    v2 := v2 + v1;
    v1 := ((v1 shl 13) or (v1 shr (32-13))) //ROTL(v1, 13)
          xor v2;
    v2 := (v2 shl 16) or (v2 shr (32-16)); //ROTL(v2, 16);
  end;

  {$ifdef DEBUG_SIPHASH}
  procedure TRACE(); inline;
  begin
    printf('(%3u) v0 %.8x'+NL, [data_len, v0]);
    printf('(%3u) v1 %.8x'+NL, [data_len, v1]);
    printf('(%3u) v2 %.8x'+NL, [data_len, v2]);
    printf('(%3u) v3 %.8x'+NL, [data_len, v3]);
  end;
  {$endif}

begin
  ni := data;
  kk := K;
  v0 := halfV0_base;
  v1 := halfV1_base;
  v2 := halfV2_base;
  v3 := halfV3_base;
  k0 := PUInt32(kk)^;
  k1 := PUInt32(kk + 4)^;
  ni_end := ni + (data_len - (data_len mod 4));
  left := data_len and 3;
  b := UInt32(data_len) shl 24;
  v3 := v3 xor k1;
  v2 := v2 xor k0;
  v1 := v1 xor k1;
  v0 := v0 xor k0;

  if out_len = half_out_len_8b then
    v1 := v1 xor $ee;

  while ni <> ni_end do
  begin
    m := PUInt32(ni)^;
    v3 := v3 xor m;
    {$ifdef DEBUG_SIPHASH}TRACE();{$endif}
    SIPROUND(); // cROUNDS = 1
    v0 := v0 xor m;
    inc(ni, 4);
  end;

  m := 0;
  while left > 0 do
  begin
    dec(left);
    m := (m shl 8) or UInt32(ni[left]);
  end;
  b := b or m;

  v3 := v3 xor b;
  {$ifdef DEBUG_SIPHASH}TRACE();{$endif}
  SIPROUND(); // cROUNDS = 1
  v0 := v0 xor b;

  if out_len = half_out_len_8b then
    v2 := v2 xor $ee
  else
    v2 := v2 xor $ff;

  {$ifdef DEBUG_SIPHASH}TRACE();{$endif}
  SIPROUND(); // dROUNDS = 3
  SIPROUND();
  SIPROUND();

  b := v1 xor v3;
  PUInt32(out_buf)^ := b;

  if out_len = half_out_len_4b then
    Exit;

  v1 := v1 xor $dd;

  {$ifdef DEBUG_SIPHASH}TRACE();{$endif}
  SIPROUND(); // dROUNDS = 3
  SIPROUND();
  SIPROUND();

  b := v1 xor v3;
  PUInt32(out_buf + 4)^ := b;

end;

end.

