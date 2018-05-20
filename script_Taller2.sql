/*

TALLER 2 - BASE DE DATOS

LINK VIDEO DE SUSTENTACION:
https://www.youtube.com/watch?v=npw-XtMKixs


LINK DE ARTICULOS NARRATIVOS
https://www.buzzsprout.com/episodes/706805-taller-2-narracion-de-articulos

*/

/*
PUNTO 0
Adecuaciones del modelo
*/

-- Creamos el campo estado
ALTER TABLE AVIONES
ADD ESTADO VARCHAR(15);


-- Creamos un check constraint para los estados de los aviones.
ALTER TABLE AVIONES
ADD CONSTRAINT CK_AVIONES_ESTADO 
CHECK (ESTADO in('Vuelo', 'Tierra', 'Mantenimiento', 'Reparación'));

--Creamos un check constraint para los estados del itinerario de vuelos.
ALTER TABLE ITINERARIOS
ADD CONSTRAINT CK_ITINERARIOS_ESTADO 
CHECK (ESTADO in('En Vuelo', 'Cancelado', 'Retrasado', 'Confirmado', 'Abordando', 'Programado'));

--Creamos la tabla Vuelos confirmados la cual guarda el estado
--de un vuelo y el aeropuerto en que se encuentra segun las adecuaciones.
CREATE TABLE VUELOS_CONFIRMADOS(
ID INT PRIMARY KEY,
VUELO_ID INT,
AEROPUERTO_ACTUAL INT,
AEROPUERTO_MANTENIMIENTO INT
);

--Relaciones de la tablas.
ALTER TABLE VUELOS_CONFIRMADOS
ADD CONSTRAINT fk_VUELOS_CONF_VUELO
foreign key (VUELO_ID)
references VUELOS (id);

ALTER TABLE VUELOS_CONFIRMADOS
ADD CONSTRAINT fk_VUELOS_CONF_AEROPUERTO_AC
foreign key (AEROPUERTO_ACTUAL)
references AEROPUERTOS (id);

ALTER TABLE VUELOS_CONFIRMADOS
ADD CONSTRAINT fk_VUELOS_CONF_AEROPUERTO_MN
foreign key (AEROPUERTO_MANTENIMIENTO)
references AEROPUERTOS (id);

--Secuencia de la nueva tabla
CREATE SEQUENCE id_VUELOS_CONFIRMADOS
INCREMENT BY 1 
START WITH 1 MINVALUE 1;


/*
PUNTO 1
Vista que trae la informacion basica de los vuelos en progreso para el 
procedimiento del punto 2.
*/
CREATE OR REPLACE VIEW Vuelos_Progreso
AS
SELECT 
    i.id itinerario_id,
    fecha_estimada_salida,
    fecha_real_salida,
    fecha_estimada_llegada,
    fecha_real_llegada,
    i.estado,
    R.AEROPUERTO_DESTINO_ID,
    R.AEROPUERTO_ORIGEN_ID,
    i.AVION_ID
FROM ITINERARIOS I
    INNER JOIN VUELOS V ON V.ID = I.VUELO_ID
    INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
ORDER BY fecha_estimada_llegada DESC;

/*
PUNTO 2
Procedimiento que realiza la Programacion de Tripulacion para el Vuelo.
*/
CREATE OR REPLACE PROCEDURE prog_Tripulacion(vuelo_id IN int) IS
    avion_id int;
    piloto_id int;
    copiloto_id int;
    total_asientos int;
BEGIN
    
    DECLARE
    vuelo int := vuelo_id;
    BEGIN
    
    -- Asignacion del avion       
    SELECT VP.AVION_ID
    INTO avion_id
    FROM VUELOS_PROGRESO VP --> vista
    WHERE VP.AEROPUERTO_DESTINO_ID = (SELECT R.AEROPUERTO_ORIGEN_ID 
                                      FROM VUELOS V 
                                        INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                      WHERE V.ID = vuelo) --> Filtrado por aeropuerto de salida                      
        AND abs( extract(HOUR FROM (VP.FECHA_ESTIMADA_LLEGADA - 
                                    (SELECT I.FECHA_ESTIMADA_salida
                                     FROM VUELOS V 
                                        INNER JOIN ITINERARIOS I ON I.VUELO_ID = V.ID
                                    WHERE V.ID = vuelo)))) <= 2 --> Filtrado por tiempo minimo para salir
        AND ROWNUM = 1;
    

    DBMS_OUTPUT.PUT_LINE(avion_id);
    
    -- Asignacion de PILOTO
    SELECT P.ID
    INTO piloto_id
    FROM EMPLEADOS E
        INNER JOIN PILOTOS P ON P.EMPLEADO_ID = E.ID
    WHERE E.ESTADO = 'ACTIVO' 
        AND P.TIPO_CARGO = 'PILOTO'
        AND E.HORAS_DESCANSO > 2
        AND E.CIUDAD_ID = (  SELECT C.ID
                             FROM VUELOS V
                                INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                INNER JOIN AEROPUERTOS AE ON R.AEROPUERTO_ORIGEN_ID = AE.ID
                                INNER JOIN CIUDADES C ON AE.CIUDAD_ID = C.ID
                             WHERE V.ID = vuelo)
        AND ROWNUM = 1;
        
    DBMS_OUTPUT.PUT_LINE(piloto_id);
    
    -- Asignacion de COPILOTO
    SELECT P.ID
    INTO copiloto_id
    FROM EMPLEADOS E
        INNER JOIN PILOTOS P ON P.EMPLEADO_ID = E.ID
    WHERE E.ESTADO = 'ACTIVO' 
        AND P.TIPO_CARGO = 'COPILOTO'
        AND E.HORAS_DESCANSO > 2
        AND E.CIUDAD_ID = (  SELECT C.ID
                             FROM VUELOS V
                                INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                INNER JOIN AEROPUERTOS AE ON R.AEROPUERTO_ORIGEN_ID = AE.ID
                                INNER JOIN CIUDADES C ON AE.CIUDAD_ID = C.ID
                             WHERE V.ID = vuelo)
        AND ROWNUM = 1;
        
    DBMS_OUTPUT.PUT_LINE(copiloto_id);
    
    --Actualizo el itinerario con el avion y pilotos...
    DECLARE
    avion_u int := avion_id;
    piloto_u int := piloto_id;
    copiloto_u int := copiloto_id;
    BEGIN
        
        -- Actualizo el estado del itinerario de vuelo con su
        -- tripulacion y estado
        UPDATE ITINERARIOS 
        SET AVION_ID = avion_u,
            PILOTO_ID = piloto_u,
            COPILOTO_ID = copiloto_u,
            ESTADO = 'Confirmado'
        WHERE ID = (SELECT I.ID 
                    FROM VUELOS V 
                        INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
                    WHERE V.ID = vuelo);
        
        --Confirmo el vuelo en la nueva tabla de vuelos confirmados.            
        INSERT INTO VUELOS_CONFIRMADOS (ID, VUELO_ID)
        VALUES (id_VUELOS_CONFIRMADOS.NEXTVAL, vuelo_id);
    END;
    
    
    --Query de asientos del avion que se asigno.
    SELECT A.asientos_ejecutivos + A.asientos_economicos + A.asientos_estandar
    INTO total_asientos
    FROM AVIONES A
    WHERE A.ID = avion_id;
    
    
    DBMS_OUTPUT.PUT_LINE(total_asientos);
    
    -- Business logic por asiento y asignacion de tripulantes.
    IF total_asientos > 0 AND total_asientos <= 19 then
        
        INSERT INTO TRIPULANTE_PROGRAMACIONES (id, ITINERARIO_ID, EMPLEADO_ID)
            SELECT id_tripulante_prog.NEXTVAL, 
                (SELECT I.ID 
                 FROM VUELOS V 
                    INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
                    WHERE V.ID = vuelo),
                E.ID 
        FROM EMPLEADOS E
        WHERE E.TIPO_EMPLEADO = 'Tripulante'
            AND E.ESTADO = 'ACTIVO'
            AND E.HORAS_DESCANSO > 2
            AND E.CIUDAD_ID = (  SELECT C.ID
                                FROM VUELOS V
                                   INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                   INNER JOIN AEROPUERTOS AE ON R.AEROPUERTO_ORIGEN_ID = AE.ID
                                   INNER JOIN CIUDADES C ON AE.CIUDAD_ID = C.ID
                                WHERE V.ID = vuelo)
        AND ROWNUM = 1;
    ELSIF total_asientos > 19  AND total_asientos <= 50 then

            INSERT INTO TRIPULANTE_PROGRAMACIONES (id, ITINERARIO_ID, EMPLEADO_ID)
            SELECT id_tripulante_prog.NEXTVAL, 
                (SELECT I.ID 
                 FROM VUELOS V 
                    INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
                    WHERE V.ID = vuelo),
                E.ID 
            FROM EMPLEADOS E
            WHERE E.TIPO_EMPLEADO = 'Tripulante'
                AND E.ESTADO = 'ACTIVO'
                AND E.HORAS_DESCANSO > 2
                AND E.CIUDAD_ID = (  SELECT C.ID
                                    FROM VUELOS V
                                       INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                       INNER JOIN AEROPUERTOS AE ON R.AEROPUERTO_ORIGEN_ID = AE.ID
                                       INNER JOIN CIUDADES C ON AE.CIUDAD_ID = C.ID
                                    WHERE V.ID = vuelo)
            AND ROWNUM <= 1;
            
            
            INSERT INTO TRIPULANTE_PROGRAMACIONES (id, ITINERARIO_ID, EMPLEADO_ID)
            SELECT id_tripulante_prog.NEXTVAL, 
                (SELECT I.ID 
                 FROM VUELOS V 
                    INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
                    WHERE V.ID = vuelo),
                E.ID 
            FROM EMPLEADOS E
            WHERE E.TIPO_EMPLEADO = 'Auxiliar de Servicio'
                AND E.ESTADO = 'ACTIVO'
                AND E.HORAS_DESCANSO > 2
                AND E.CIUDAD_ID = (  SELECT C.ID
                                    FROM VUELOS V
                                       INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                       INNER JOIN AEROPUERTOS AE ON R.AEROPUERTO_ORIGEN_ID = AE.ID
                                       INNER JOIN CIUDADES C ON AE.CIUDAD_ID = C.ID
                                    WHERE V.ID = vuelo)
            AND ROWNUM <= 2;
    ELSIF total_asientos > 50  AND total_asientos <= 180 then
    
            INSERT INTO TRIPULANTE_PROGRAMACIONES (id, ITINERARIO_ID, EMPLEADO_ID)
            SELECT id_tripulante_prog.NEXTVAL, 
                (SELECT I.ID 
                 FROM VUELOS V 
                    INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
                    WHERE V.ID = vuelo),
                E.ID
            FROM EMPLEADOS E
            WHERE E.TIPO_EMPLEADO = 'Tripulante'
                AND E.ESTADO = 'ACTIVO'
                AND E.HORAS_DESCANSO > 2
               AND E.CIUDAD_ID = (  SELECT C.ID
                                   FROM VUELOS V
                                      INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                      INNER JOIN AEROPUERTOS AE ON R.AEROPUERTO_ORIGEN_ID = AE.ID
                                      INNER JOIN CIUDADES C ON AE.CIUDAD_ID = C.ID
                                   WHERE V.ID = vuelo)
            AND ROWNUM <= (total_asientos / 50);
            
            
            INSERT INTO TRIPULANTE_PROGRAMACIONES (id, ITINERARIO_ID, EMPLEADO_ID)
            SELECT id_tripulante_prog.NEXTVAL, 
                (SELECT I.ID 
                 FROM VUELOS V 
                    INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
                    WHERE V.ID = vuelo),
                E.ID 
            FROM EMPLEADOS E
            WHERE E.TIPO_EMPLEADO = 'Auxiliar de Servicio'
                AND E.ESTADO = 'ACTIVO'
                AND E.HORAS_DESCANSO > 2
               AND E.CIUDAD_ID = (  SELECT C.ID
                                   FROM VUELOS V
                                      INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                      INNER JOIN AEROPUERTOS AE ON R.AEROPUERTO_ORIGEN_ID = AE.ID
                                      INNER JOIN CIUDADES C ON AE.CIUDAD_ID = C.ID
                                   WHERE V.ID = vuelo)
            AND ROWNUM <= 4;
    ELSE 

            INSERT INTO TRIPULANTE_PROGRAMACIONES (id, ITINERARIO_ID, EMPLEADO_ID)
            SELECT id_tripulante_prog.NEXTVAL, 
                (SELECT I.ID 
                 FROM VUELOS V 
                    INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
                    WHERE V.ID = vuelo),
                E.ID 
            FROM EMPLEADOS E
            WHERE E.TIPO_EMPLEADO = 'Tripulante'
                AND E.ESTADO = 'ACTIVO'
                AND E.HORAS_DESCANSO > 2
                AND E.CIUDAD_ID = (  SELECT C.ID
                                    FROM VUELOS V
                                       INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                       INNER JOIN AEROPUERTOS AE ON R.AEROPUERTO_ORIGEN_ID = AE.ID
                                       INNER JOIN CIUDADES C ON AE.CIUDAD_ID = C.ID
                                    WHERE V.ID = vuelo)
            AND ROWNUM <= (total_asientos / 50);
            
            
            INSERT INTO TRIPULANTE_PROGRAMACIONES (id, ITINERARIO_ID, EMPLEADO_ID)
            SELECT id_tripulante_prog.NEXTVAL, 
                (SELECT I.ID 
                 FROM VUELOS V 
                    INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
                    WHERE V.ID = vuelo),
                E.ID 
            FROM EMPLEADOS E
            WHERE E.TIPO_EMPLEADO = 'Auxiliar de Servicio'
                AND E.ESTADO = 'ACTIVO'
                AND E.HORAS_DESCANSO > 2
                AND E.CIUDAD_ID = (  SELECT C.ID
                                    FROM VUELOS V
                                       INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                       INNER JOIN AEROPUERTOS AE ON R.AEROPUERTO_ORIGEN_ID = AE.ID
                                       INNER JOIN CIUDADES C ON AE.CIUDAD_ID = C.ID
                                    WHERE V.ID = vuelo)
            AND ROWNUM <= (SELECT CASE WHEN R.DURACION_PROMEDIO >= 6 THEN 19 ELSE 18 END
                           FROM VUELOS V
                                INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                           WHERE V.ID = 4);
    END IF;
    
    END;    
END;

/*  

    EXEC prog_Tripulacion (4);
    SELECT * FROM ITINERARIOS;
    SELECT * FROM TRIPULANTE_PROGRAMACIONES;
    SELECT * FROM VUELOS_CONFIRMADOS;

*/

/*
PUNTO 3
Procedimiento que realiza el check in de los pasajeros y sus estados.
*/
CREATE OR REPLACE PROCEDURE realizar_CheckIn(
    vuelo_id IN int, 
    pasajero_id IN int, 
    tipo_Asiento IN varchar) 
IS
    vuelo int := vuelo_id;
    pasajero int := pasajero_id;
    asiento varchar(30) := tipo_Asiento;
    total_asientos int;
    total_confirmados int;
BEGIN
    
    -- Insertamos el nuevo registro a la tabla check in 
    INSERT INTO CHECK_IN (ID, PASAJERO_ID, ITINERARIO_ID, 
                          CIUDAD_ID, HORA_CHECK_IN)
    SELECT 
        id_check_in.NEXTVAL,
        P.ID,
        I.ID,
        A.CIUDAD_ID,
        sysdate
    FROM VUELOS V 
        INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
        INNER JOIN PASAJEROS P ON P.ID = pasajero
        INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
        INNER JOIN AEROPUERTOS A ON A.ID = R.AEROPUERTO_ORIGEN_ID
    WHERE V.ID = vuelo;
    
    DBMS_OUTPUT.PUT_LINE('CHECK IN OK!');
    
    --Consulto los asientos del avion
    SELECT A.asientos_ejecutivos + A.asientos_economicos + A.asientos_estandar
    INTO total_asientos
    FROM VUELOS V 
        INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
        INNER JOIN AVIONES A ON A.ID = I.AVION_ID
    WHERE V.ID = vuelo;
    
    --Consulto los asientos asignados reales del avion.
    SELECT I.PASAJEROS_ECONOMICA + i.PASAJEROS_EJECUTIVA
    INTO total_confirmados
    FROM VUELOS V 
        INNER JOIN ITINERARIOS i ON V.ID = I.VUELO_ID 
    WHERE V.ID = vuelo;
    
    --Validar que si hayan asientos disponibles...
    IF (total_confirmados < total_asientos)
        THEN
            --Actualizo el itinerario con los asientos asignados en el vuelo.
            UPDATE ITINERARIOS 
            SET PASAJEROS_ECONOMICA = PASAJEROS_ECONOMICA + CASE WHEN asiento = 'ECONOMICA' THEN 1 ELSE 0 END,
                PASAJEROS_EJECUTIVA = PASAJEROS_EJECUTIVA + CASE WHEN asiento = 'EJECUTIVA' THEN 1 ELSE 0 END
            WHERE ID = (SELECT I.ID 
                        FROM VUELOS V 
                            INNER JOIN ITINERARIOS I ON V.ID = I.VUELO_ID 
                        WHERE V.ID = vuelo);
                                   
            DBMS_OUTPUT.PUT_LINE('CHECK IN STATUS OK!');
        END IF;
    
END;

/*

    EXEC realizar_CheckIn(4, 9, 'ECONOMICA');
    SELECT * FROM CHECK_IN;
    SELECT * FROM ITINERARIOS;
    
*/



/*
PUNTO 4
Vista que trae la informacion de un vuelo y sus tripulantes en el tiempo,
Aqui creamos varias vistas para traer la final.
*/

--Vista para informacion de Pilotos y Copilotos
CREATE OR REPLACE VIEW PILOTOS_DATA
AS
    SELECT P.ID, P.HORAS_VUELO, P.TIPO_CARGO, 
        E.NOMBRE, E.APELLIDO, E.SEXO, E.HORAS_DESCANSO, E.ESTADO
    FROM PILOTOS P 
        INNER JOIN EMPLEADOS E ON E.ID = P.EMPLEADO_ID;

--Vista para informacion de Tripulacion auxiliar del vuelo  
CREATE OR REPLACE VIEW TRIPULATION_DATA
AS
    SELECT E.ID, E.NOMBRE, E.APELLIDO, E.SEXO, 
        E.HORAS_DESCANSO, E.ESTADO, E.TIPO_EMPLEADO
    FROM EMPLEADOS E
    WHERE TIPO_EMPLEADO IN ('Tripulante','Auxiliar de Servicio');

--Vista Final
CREATE OR REPLACE VIEW FLIGHT_TRIPULATION
AS
    SELECT
        I.VUELO_ID,
        P.ID PILOTO_ID, 
        P.NOMBRE||' '||P.APELLIDO NOMBRE_PILOTO,
        'PILOTO' TRIPULANTE
    FROM ITINERARIOS I  
        INNER JOIN PILOTOS_DATA P ON P.ID = I.PILOTO_ID
    UNION
    SELECT 
        I.VUELO_ID,
        COP.ID COPILOTO_ID, 
        COP.NOMBRE||' '||COP.APELLIDO NOMBRE_COPILOTO,
        'COPILOTO' TRIPULANTE
    FROM ITINERARIOS I
        INNER JOIN PILOTOS_DATA COP ON COP.ID = I.COPILOTO_ID
    UNION
    SELECT
        I.VUELO_ID,
        TRIP.ID TRIPULANTE_ID, 
        TRIP.NOMBRE||' '||TRIP.APELLIDO NOMBRE_TRIPULANTE,
        UPPER(TRIP.TIPO_EMPLEADO) TRIPULANTE
    FROM ITINERARIOS I
        INNER JOIN TRIPULANTE_PROGRAMACIONES T ON I.ID = T.ITINERARIO_ID
        INNER JOIN TRIPULATION_DATA TRIP ON TRIP.ID = T.EMPLEADO_ID;
        
/*
    
    SELECT *
    FROM FLIGHT_TRIPULATION
    WHERE VUELO_ID = 4

*/

/*
PUNTO 5
Vista que trae el calendario de rutas y vuelos para consultar salidas
en un lapso de dos semanas.
*/

CREATE OR REPLACE VIEW FLIGHT_SCHEDULES
AS
SELECT R.ID RUTA_ID, V.ID VUELO_ID, 
    FECHA_ESTIMADA_SALIDA,
    TO_CHAR(I.FECHA_ESTIMADA_SALIDA, 'HH24:MI:SS') HORA_SALIDA,
    TO_CHAR(I.FECHA_ESTIMADA_SALIDA, 'dd/MM/yyyy') FECHA_SALIDA
FROM ITINERARIOS I
    INNER JOIN VUELOS V ON I.VUELO_ID = V.ID
    INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
WHERE   FECHA_ESTIMADA_SALIDA  >= TRUNC (FECHA_ESTIMADA_SALIDA, 'IW')
    AND     FECHA_ESTIMADA_SALIDA  <  TRUNC (FECHA_ESTIMADA_SALIDA,   'IW') + 2;
    
    
/*

    SELECT * 
    FROM FLIGHT_SCHEDULES
    WHERE RUTA_ID = 2;  
    
*/


/*
PUNTO 6
Planes de ejecucion.
*/

/*
Explain plan para la vista usada en el procedimiento del punto 2.
En este caso pasamos un id de vuelo de ejemplo para mostrarnos el plan
de ejecucion de la consulta
*/
EXPLAIN PLAN 
  SET statement_id = 'ex_plan_View2' FOR
    SELECT VP.AVION_ID
    FROM VUELOS_PROGRESO VP --> vista
    WHERE VP.AEROPUERTO_DESTINO_ID = (SELECT R.AEROPUERTO_ORIGEN_ID 
                                      FROM VUELOS V 
                                        INNER JOIN RUTAS R ON R.ID = V.RUTA_ID
                                      WHERE V.ID = 4)                       
        AND abs( extract(HOUR FROM (VP.FECHA_ESTIMADA_LLEGADA - 
                                    (SELECT I.FECHA_ESTIMADA_salida
                                     FROM VUELOS V 
                                        INNER JOIN ITINERARIOS I ON I.VUELO_ID = V.ID
                                    WHERE V.ID = 4)))) <= 2
        AND ROWNUM = 1;
    
    
SELECT PLAN_TABLE_OUTPUT 
FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'ex_plan_View2','ADVANCED'));

/*
Explain plan para la vista usada en el procedimiento del punto 4.
En este caso pasamos un id de vuelo de ejemplo para mostrarnos el plan
de ejecucion de la consulta para traer la tripulacion de un vuelo.
*/
EXPLAIN PLAN 
  SET statement_id = 'ex_plan_View4' FOR
  SELECT *
    FROM FLIGHT_TRIPULATION
    WHERE VUELO_ID = 4;
    
    
SELECT PLAN_TABLE_OUTPUT 
FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'ex_plan_View4','ADVANCED'));

/*
Explain plan para la vista usada en el procedimiento del punto 5.
En este caso pasamos un id de Ruta de ejemplo para mostrarnos el plan
de ejecucion de la consulta para traer la tripulacion de un vuelo.
*/
EXPLAIN PLAN 
  SET statement_id = 'ex_plan_View5' FOR
  SELECT * 
    FROM FLIGHT_SCHEDULES
    WHERE RUTA_ID = 2;
    
    
SELECT PLAN_TABLE_OUTPUT 
FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, 'ex_plan_View5','ADVANCED'));