scl = 12
sda = 13
current_type = 250 -- Константа C https://en.wikipedia.org/wiki/Light_meter#Calibration_constants

gpio.set_mode(scl, gpio.OUTPUT)
gpio.set_mode(sda, gpio.OUTPUT)

bh1750_address = 0x23

state = state or {} 
if state.iso_index == nil then state.iso_index = 4 end
if state.aperture_index == nil then state.aperture_index = 2 end
if state.measurement_mode == nil then state.measurement_mode = 1 end

-- I2C функції
function i2c_start()
    gpio.write(sda, gpio.HIGH)
    gpio.write(scl, gpio.HIGH)
    gpio.write(sda, gpio.LOW)
    gpio.write(scl, gpio.LOW)
end

function i2c_stop()
    gpio.write(sda, gpio.LOW)
    gpio.write(scl, gpio.HIGH)
    gpio.write(sda, gpio.HIGH)
end

function i2c_write_byte(byte)
    for i = 7, 0, -1 do
        gpio.write(sda, (byte >> i) & 1)
        gpio.write(scl, gpio.HIGH)
        gpio.write(scl, gpio.LOW)
    end
    gpio.set_mode(sda, gpio.INPUT)
    gpio.write(scl, gpio.HIGH)
    local ack = gpio.read(sda) == 0
    gpio.write(scl, gpio.LOW)
    gpio.set_mode(sda, gpio.OUTPUT)
    return ack
end

function i2c_read_byte(ack)
    local byte = 0
    gpio.set_mode(sda, gpio.INPUT)
    for i = 7, 0, -1 do
        gpio.write(scl, gpio.HIGH)
        byte = (byte << 1) | gpio.read(sda)
        gpio.write(scl, gpio.LOW)
    end
    gpio.set_mode(sda, gpio.OUTPUT)
    gpio.write(sda, ack and 0 or 1)
    gpio.write(scl, gpio.HIGH)
    gpio.write(scl, gpio.LOW)
    return byte
end

-- Ініціалізація BH1750
function bh1750_init()
    i2c_start()
    i2c_write_byte(bh1750_address << 1)
    i2c_write_byte(0x10)
    i2c_stop()
end

function bh1750_read_lux()
    i2c_start()
    i2c_write_byte((bh1750_address << 1) | 1)
    local msb = i2c_read_byte(true)
    local lsb = i2c_read_byte(false)
    i2c_stop()
    return ((msb << 8) + lsb) / 1.2
end

bh1750_init()

-- Таблиці значень
local iso_values = {
  12, 25, 50, 100, 200, 400, 800, 1600, 3200
}
local aperture_values = {
  1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.0, 16.0
}
local shutter_speeds = {
    1/8000, 1/4000, 1/2000, 1/1000, 1/500, 1/250, 1/125, 1/60, 1/30, 1/15, 1/8, 1/4, 1/2, 1, 2, 4, 8, 15, 30
}

local function find_closest_shutter(speed)
    local closest = shutter_speeds[1]
    for _, val in ipairs(shutter_speeds) do
        if math.abs(speed - val) < math.abs(speed - closest) then
            closest = val
        end
    end
    return closest >= 1 and string.format("%ds", closest) or string.format("1/%d", math.floor(1 / closest + 0.5))
end

function calculate_ev(lux)
    return lux > 0 and (math.log((lux * 100) / current_type) / math.log(2)) or 0
end

function calculate_exposure(lux, aperture, iso)
    return lux > 0 and (current_type * aperture^2) / (lux * iso) or 0
end

function lilka.update()
    local controller_state = controller.get_state()
    
    if controller_state.select.just_pressed then
        util.exit()
    end
    if controller_state.a.just_pressed then
        state.aperture_index = (state.aperture_index % #aperture_values) + 1
    end
    if controller_state.c.just_pressed then
        state.iso_index = (state.iso_index % #iso_values) + 1
    end
end

function lilka.draw()
    display.fill_screen(display.color565(0, 0, 0))
    
    local lux = bh1750_read_lux()
    local iso = iso_values[state.iso_index]
    local aperture = aperture_values[state.aperture_index]
    
    local ev = calculate_ev(lux, iso)
    local exposure = calculate_exposure(lux, aperture, iso)
    local shutter = lux > 65535 and "Overload" or (lux > 1 and find_closest_shutter(exposure) or "Not enough light")
    display.set_cursor(10, 30)
    display.print("Incident Light")
    display.set_cursor(10, 50)
    display.print(string.format("ISO: %-4d  Aperture: f/%.1f", iso, aperture))
    display.set_cursor(10, 90)
    display.print("Shutter: " .. shutter)
    
    display.set_cursor(10, 200)
    display.print("C: ISO")
    display.set_cursor(10, 220)
    display.print("A: Aperture   Select: Exit")
end