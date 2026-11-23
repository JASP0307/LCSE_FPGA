INSTRUCCIONES PARA PROBAR EL BLOQUE RS232 EN LA PLACA NEXYS-A7

El fichero PICtop es adecuado para verificar el sistema en simulación,
pero puesto que no tenemos acceso a la RAM es dificil realizar la prueba 
en placa (tanto transmision como recepción).


1. USO DE LA PLACA

- El punto decimal del display inferior parpadea cuando el sistema está en funcionamiento.
- El interruptor SW(15) está conectado a la señal de Reset, activa a nivel bajo. 
- El resto de interruptiores SW(14:0) no se usan. 
- El LED(15) muestra el estado de la señal de reset. 
- Los LED(14:8) no se usan. 
- Los LEDs(7:0) muestran el estado de los switches remotos.

**** Con esta configuración, si se pone el cable de microUSB y se configura 
el puerto serie adecuadamente, los datos pueden enviarse de forma serie 
desde el PC hasta las posiciones 0-2 de la RAM, y desde la posiciones 4-5 
de la RAM hasta el PC utilizando el protocolo RS232. 

**** Para verificar el funcionamiento de la recepción desde el PC, 
se recomienda modificar la DMA para que escriba siempre en la posicion 31 
de la RAM (con lo que se podria ver el resultado de cada escritura en los 
dos displays activos). 

**** Para verificar el funcionamiento de la transmisión hacia el PC 
habria que generar un pulso de SEND_COMM (por ejemplo cada vez que se pulsa 
un boton o se escribe en la RAM), de forme que se envien los datos de las 
posiciones 4 y 5 de la RAM al PC (en cualquier caso esto implicaría 
modificar levemente el fichero PICtop.vhd). 


2. FICHEROS ADICIONALES QUE SE ENTREGAN

- Nexys_PICtop.vhd   
Es el fichero que traslada los nombres de los puertos de nuestro diseño a los nombres de la Nexys A7. 
Es decir, realiza las conexiones de los nombres del PICtop a los LEDs, Switches, Displays, etc.
(incluye la conversión de la frecuencia de reloj de 100 MHz a 20MHz)

- Nexys_PICtop.xdc
Fichero de restricciones, con los componentes que se utilizan en este diseño.

- tb_nexys_PICtop.vhd
Fichero de estimulos de la placa, para la simulación con retardos. 
Contiene las conexiones de los componentes de la placa a los nombres del PICtop (es decir, invierte los cambios de nombre realizados en Nexys_PICtop.vhd), 
y genera los estimulos utilizando las señales originales (es decir, el proceso de los estimulos es el mismo que el que hay en tb_PICtop.vhd). 


3. MODIFICACIONES NECESARIAS EN LOS FICHEROS DE DISEÑO

- En caso de haber incluido el divisor de frecuencia de reloj de 100MHz a 20MHz en el fichero PICtop.vhd es necesario eliminarlo de dicho fichero
(debe estar incluido en el fichero Nexys_PICtop.vhd).

