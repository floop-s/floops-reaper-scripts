-- @noindex
-- @description Floop Hunter Framework - DSP utilities
-- @author Floop-s
-- @license GPL-3.0
local DSP = {}

local min, max, floor, abs, sqrt, log = math.min, math.max, math.floor, math.abs, math.sqrt, math.log
local sin, cos, pi = math.sin, math.cos, math.pi

function DSP.db_to_amp(db) return 10 ^ (db / 20) end

function DSP.amp_to_db(amp) return 20 * (log(max(amp, 1e-12)) / log(10)) end

-- Median calculation
function DSP.median(tbl)
  local n = #tbl
  if n == 0 then return 0.0 end
  local a = {}
  for i = 1, n do a[i] = tbl[i] end
  table.sort(a)
  if n % 2 == 1 then return a[math.ceil(n / 2)] else return 0.5 * (a[n / 2] + a[n / 2 + 1]) end
end

-- Percentile (p in [0, 1]).
function DSP.percentile(tbl, p)
  local n = #tbl
  if n == 0 then return 0.0 end
  local a = {}
  for i = 1, n do a[i] = tbl[i] end
  table.sort(a)
  local idx = (n - 1) * p + 1
  local k = math.floor(idx)
  local d = idx - k
  if k <= 0 then return a[1] end
  if k >= n then return a[n] end
  return a[k] + d * (a[k + 1] - a[k])
end

-- RBJ Filter Coefficients
function DSP.rbj_lowpass(fc, Q, fs)
  local w0 = 2 * pi * fc / fs
  local cosw0 = cos(w0)
  local sinw0 = sin(w0)
  local alpha = sinw0 / (2 * Q)

  local b0 = (1 - cosw0) / 2
  local b1 = 1 - cosw0
  local b2 = (1 - cosw0) / 2
  local a0 = 1 + alpha
  local a1 = -2 * cosw0
  local a2 = 1 - alpha

  return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

function DSP.rbj_highpass(fc, Q, fs)
  local w0 = 2 * pi * fc / fs
  local cosw0 = cos(w0)
  local sinw0 = sin(w0)
  local alpha = sinw0 / (2 * Q)

  local b0 = (1 + cosw0) / 2
  local b1 = -(1 + cosw0)
  local b2 = (1 + cosw0) / 2
  local a0 = 1 + alpha
  local a1 = -2 * cosw0
  local a2 = 1 - alpha

  return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

function DSP.rbj_bandpass(fc, Q, fs)
  local w0 = 2 * pi * fc / fs
  local cosw0 = cos(w0)
  local sinw0 = sin(w0)
  local alpha = sinw0 / (2 * Q)

  local b0 = alpha
  local b1 = 0
  local b2 = -alpha
  local a0 = 1 + alpha
  local a1 = -2 * cosw0
  local a2 = 1 - alpha

  return { b0 = b0 / a0, b1 = b1 / a0, b2 = b2 / a0, a1 = a1 / a0, a2 = a2 / a0 }
end

-- Biquad Implementation
function DSP.biquad_new(coeff)
  return { b0 = coeff.b0, b1 = coeff.b1, b2 = coeff.b2, a1 = coeff.a1, a2 = coeff.a2, x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0 }
end

function DSP.biquad_process(st, x)
  local y = st.b0 * x + st.b1 * st.x1 + st.b2 * st.x2 - st.a1 * st.y1 - st.a2 * st.y2
  st.x2 = st.x1; st.x1 = x
  st.y2 = st.y1; st.y1 = y
  return y
end

-- RMS Calculation
function DSP.calculate_rms_db(buf, n)
  local sum = 0.0
  local count = n or #buf
  if count == 0 then return -144.0 end

  for i = 1, count do
    sum = sum + buf[i] * buf[i]
  end

  local rms = sqrt(sum / count)
  return DSP.amp_to_db(rms)
end

return DSP
