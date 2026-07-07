unit siphash_1_3;

{$mode ObjFPC}{$H+}
{$i defines.inc}
(*
  This is translation of SipHash reference C implementation
  from [https://github.com/veorq/SipHash/blob/master/siphash.c]
  and [https://github.com/veorq/SipHash/blob/master/halfsiphash.c]
  using cROUNDS=1 and dROUNDS=3
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

procedure siphash_1_3(const data: Pointer; const data_len: SizeInt; const K: Pointer;
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

procedure halfsiphash_1_3(const data: Pointer; const data_len: SizeInt; const K: Pointer;
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

procedure siphash_1_3(const data: Pointer; const data_len: SizeInt; const K: Pointer;
  const out_buf: PByte; const out_len: siphash_out_length);
var
  ni, ni_end: PByte;
  kk: PByte;
  v0, v1, v2, v3,
  k0, k1,
  m, b: UInt64;
  left: Integer;

  { #define ROTL(x, b) (uint64_t)(((x) << (b)) | ((x) >> (64 - (b)))) }
  function ROTL_13(const X: UInt64): UInt64;
  begin
    Result := (X shl 13) or (X shr (64-13));
  end;
  function ROTL_16(const X: UInt64): UInt64;
  begin
    Result := (X shl 16) or (X shr (64-16));
  end;
  function ROTL_17(const X: UInt64): UInt64;
  begin
    Result := (X shl 17) or (X shr (64-17));
  end;
  function ROTL_21(const X: UInt64): UInt64;
  begin
    Result := (X shl 21) or (X shr (64-21));
  end;
  function ROTL_32(const X: UInt64): UInt64;
  begin
    Result := (X shl 32) or (X shr (64-32));
  end;

  procedure U32TO8_LE(const P: PByte; const V: UInt32);
  begin
    P[0] := UInt8(V);
    P[1] := UInt8(V shr 8);
    P[2] := UInt8(V shr 16);
    P[3] := UInt8(V shr 24);
  end;

  procedure U64TO8_LE(const P: PByte; const V: UInt64);
  begin
    U32TO8_LE(P, UInt32(V));
    U32TO8_LE(P + 4, UInt32(V shr 32));
  end;

  function U8TO64_LE(const P: PByte): UInt64;
  begin
    Result := P[0];
    Result := Result or (UInt64(P[1]) shl 8);
    Result := Result or (UInt64(P[2]) shl 16);
    Result := Result or (UInt64(P[3]) shl 24);
    Result := Result or (UInt64(P[4]) shl 32);
    Result := Result or (UInt64(P[5]) shl 40);
    Result := Result or (UInt64(P[6]) shl 48);
    Result := Result or (UInt64(P[7]) shl 56);
  end;

  procedure SIPROUND(); inline;
  begin
    v0 := v0 + v1;
    v1 := ROTL_13(v1)
          xor v0;
    v0 := ROTL_32(v0);
    v2 := v2 + v3;
    v3 := ROTL_16(v3)
          xor v2;
    v0 := v0 + v3;
    v3 := ROTL_21(v3)
          xor v0;
    v2 := v2 + v1;
    v1 := ROTL_17(v1)
          xor v2;
    v2 := ROTL_32(v2);
  end;

  {$ifdef DEBUG_SIPHASH}
  procedure TRACE();
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
  k0 := U8TO64_LE(kk);
  k1 := U8TO64_LE(kk + 8);
  ni_end := ni + (data_len - (data_len mod SizeOf(UInt64)));
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
    m := U8TO64_LE(ni);
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
  U64TO8_LE(out_buf, b);

  if out_len = sip_out_len_8b then
    Exit;

  v1 := v1 xor $dd;

  {$ifdef DEBUG_SIPHASH}TRACE();{$endif}
  SIPROUND(); // dROUNDS = 3
  SIPROUND();
  SIPROUND();

  b := v0 xor v1 xor v2 xor v3;
  U64TO8_LE(out_buf + 8, b);

end;

{ HalfSipHash }

const
  halfV0_base = 0;
  halfV1_base = 0;
  halfV2_base = UInt32($6c796765);
  halfV3_base = UInt32($74656462);

procedure halfsiphash_1_3(const data: Pointer; const data_len: SizeInt; const K: Pointer;
  const out_buf: PByte; const out_len: halfsiphash_out_length);
var
  ni, ni_end: PByte;
  kk: PByte;
  v0, v1, v2, v3,
  k0, k1,
  m, b: UInt32;
  left: Integer;

  { #define ROTL(x, b) (uint32_t)(((x) << (b)) | ((x) >> (32 - (b)))) }
  function ROTL_5(const X: UInt32): UInt32;
  begin
    Result := (X shl 5) or (X shr (32-5));
  end;
  function ROTL_7(const X: UInt32): UInt32;
  begin
    Result := (X shl 7) or (X shr (32-7));
  end;
  function ROTL_8(const X: UInt32): UInt32;
  begin
    Result := (X shl 8) or (X shr (32-8));
  end;
  function ROTL_13(const X: UInt32): UInt32;
  begin
    Result := (X shl 13) or (X shr (32-13));
  end;
  function ROTL_16(const X: UInt32): UInt32;
  begin
    Result := (X shl 16) or (X shr (32-16));
  end;

  procedure U32TO8_LE(const P: PByte; const V: UInt32);
  begin
    P[0] := UInt8(V);
    P[1] := UInt8(V shr 8);
    P[2] := UInt8(V shr 16);
    P[3] := UInt8(V shr 24);
  end;

  function U8TO32_LE(const P: PByte): UInt32;
  begin
    Result := P[0]
     or (UInt32(P[1]) shl 8)
     or (UInt32(P[2]) shl 16)
     or (UInt32(P[3]) shl 24);
  end;

  procedure SIPROUND(); inline;
  begin
    v0 := v0 + v1;
    v1 := ROTL_5(v1)
          xor v0;
    v0 := ROTL_16(v0);
    v2 := v2 + v3;
    v3 := ROTL_8(v3)
          xor v2;
    v0 := v0 + v3;
    v3 := ROTL_7(v3)
          xor v0;
    v2 := v2 + v1;
    v1 := ROTL_13(v1)
          xor v2;
    v2 := ROTL_16(v2);
  end;

  {$ifdef DEBUG_SIPHASH}
  procedure TRACE();
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
  k0 := U8TO32_LE(kk);
  k1 := U8TO32_LE(kk + 4);
  ni_end := ni + (data_len - (data_len mod SizeOf(UInt32)));
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
    m := U8TO32_LE(ni);
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
    m := (m shl 8) or UInt64(ni[left]);
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
  U32TO8_LE(out_buf, b);

  if out_len = half_out_len_4b then
    Exit;

  v1 := v1 xor $dd;

  {$ifdef DEBUG_SIPHASH}TRACE();{$endif}
  SIPROUND(); // dROUNDS = 3
  SIPROUND();
  SIPROUND();

  b := v1 xor v3;
  U32TO8_LE(out_buf + 8, b);

end;

end.

