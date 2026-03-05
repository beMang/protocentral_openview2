import serial
from serial.tools import list_ports

class DataPacket:
    def __init__(self, packet_type, packet_length, hr, spo2, resp, temp):
        self.packet_type = packet_type
        self.packet_length = packet_length
        self.hr = hr
        self.spo2 = spo2
        self.resp = resp
        self.temp = temp

    def __str__(self):
        return f"DataPacket(type={self.packet_type}, length={self.packet_length}, hr={self.hr}, spo2={self.spo2}, resp={self.resp}, temp={self.temp})"

    @staticmethod
    def from_bytes(packet_bytes):
        if packet_bytes[0] != start_byte or packet_bytes[-1] != stop_byte:
            raise ValueError("Invalid packet format")
        packet_type = packet_bytes[4]
        #packet length in postiion 2 and 3
        packet_length = (packet_bytes[3] << 8) | packet_bytes[2]

        if packet_length != len(packet_bytes) - 5 - 2:  #exclude header and footer
            raise ValueError("Invalid packet length")

        offset = 5
        spo2 = packet_bytes[19+offset]
        hr = packet_bytes[20+offset]
        resp = packet_bytes[21+offset]
        temp = (packet_bytes[17+offset] | (packet_bytes[18+offset] << 8)) / 100.0
        return DataPacket(packet_type, packet_length, hr, spo2, resp, temp)

# display available serial ports
availaible_ports = list(list_ports.comports())
if not availaible_ports:
    print("No serial ports found.")
else:
    print("Available serial ports:")
    for port in availaible_ports:
        print(f" - {port.device}")

user_port = input("Enter the port to use: ")
# open the serial port
ser = serial.Serial(user_port, 9600, timeout=1)
print(f"Opened serial port: {ser.name}")

# read data from the serial port
found_start = False
buffer = bytearray()

start_byte = 0x0a
stop_byte = 0x0b

try:
    while True:
        if ser.in_waiting > 0:
            byte = ser.read(1)
            if byte[0] == start_byte and not found_start:
                found_start = True
                buffer.append(byte[0])
            elif byte[0] == stop_byte and found_start:
                buffer.append(byte[0])
                try:
                    print(DataPacket.from_bytes(buffer))
                except ValueError as e:
                    print(f"Error decoding packet: {e}")
                buffer.clear()
                found_start = False
            elif found_start:
                buffer.append(byte[0])

except KeyboardInterrupt:
    print("Interrupted by user.")
    #close port
    ser.close()
    print(f"Closed serial port: {ser.name}")
