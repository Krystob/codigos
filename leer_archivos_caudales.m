%% ================== CONFIG ==================
IN_XLS  = 'C:\Users\crist\Desktop\Doctorado\datos_cuencas\valdivia\RIO_CALLE_CALLE_EN_PUPUNAHUE.xls';
OUT_CSV = 'C:\Users\crist\Desktop\Doctorado\datos_cuencas\valdivia\formateados\RIO_CALLE_CALLE_EN_PUPUNAHUE.csv';

outDir = fileparts(OUT_CSV);
if ~exist(outDir, 'dir'); mkdir(outDir); end
%% ============================================

clc; clearvars -except IN_XLS OUT_CSV outDir;

% Leer todo como celdas (robusto para .xls / .xlsx)
raw = readcell(IN_XLS);

nRows = size(raw,1);
nCols = size(raw,2);

% Función inline: celda "vacía" (NaN / '' / espacios / [])
isBlank = @(x) ( ...
    isempty(x) || ...
    (isnumeric(x) && any(isnan(x(:)))) || ...
    (isstring(x) && strlength(strtrim(x))==0) || ...
    (ischar(x)   && isempty(strtrim(x))) ...
);

% Acumuladores (dinámicos)
Fecha     = datetime.empty(0,1);
Altura    = [];
Caudal    = [];
Indicador = strings(0,1);

i = 1;
while i <= nRows

    % --- Detectar inicio de mes: col 1 = 'MES:' y col 3 = 'MM/YYYY' ---
    c1 = raw{i,1};
    c3 = raw{i,3};

    isMesRow = false;
    if (ischar(c1) || isstring(c1))
        isMesRow = strcmpi(strtrim(string(c1)), "MES:");
    end

    if ~isMesRow
        i = i + 1;
        continue;
    end

    % Parsear MM/YYYY desde columna 3
    mes_anno = string(c3);
    mes_anno = strtrim(mes_anno);

    if isBlank(mes_anno) || ~contains(mes_anno, "/")
        % Si por alguna razón no está el MM/YYYY, saltar
        i = i + 1;
        continue;
    end

    parts = split(mes_anno, "/");
    if numel(parts) < 2
        i = i + 1;
        continue;
    end

    mm = str2double(parts(1));
    yy = str2double(parts(2));
    if isnan(mm) || isnan(yy)
        i = i + 1;
        continue;
    end

    % Datos empiezan dos filas abajo (fila MES:, luego encabezados)
    startRow = i + 2;

    % --- Recorrer los 3 bloques horizontales (1-5, 6-10, 11-15) ---
    for b = 0:2
        baseCol = 1 + b*5;   % DIA, HORA, ALTURA, CAUDAL, I

        % Si el archivo tiene menos de 15 columnas, proteger
        if baseCol + 4 > nCols
            continue;
        end

        r = startRow;

        while r <= nRows

            % Si aparece el próximo "MES:" cortamos el mes (por si acaso)
            if (ischar(raw{r,1}) || isstring(raw{r,1})) && strcmpi(strtrim(string(raw{r,1})), "MES:")
                break;
            end

            dia  = raw{r, baseCol};
            hora = raw{r, baseCol+1};

            % STOP por hora vacía (regla que definiste)
            if isBlank(hora)
                break;
            end

            alt  = raw{r, baseCol+2};
            q    = raw{r, baseCol+3};
            ind  = raw{r, baseCol+4};

            % Normalizar DIA
            if isBlank(dia)
                r = r + 1;
                continue;
            end
            if isnumeric(dia)
                dd = dia;
            else
                dd = str2double(string(dia));
            end
            if isnan(dd)
                r = r + 1;
                continue;
            end
            dd = round(dd);

            % Normalizar HORA (puede ser 'HH:MM' o número Excel)
            hh = NaN; mi = NaN;
            if isnumeric(hora)
                % Hora Excel típica: fracción del día (0..1)
                if hora >= 0 && hora < 1
                    totalMin = round(hora * 24 * 60);
                    hh = floor(totalMin/60);
                    mi = mod(totalMin,60);
                else
                    % Si viene como 1330, 930, etc. (raro), intentar parsear
                    s = sprintf('%g', hora);
                    s = regexprep(s,'\D','');
                    if strlength(string(s)) >= 3
                        % ej: 930 -> 09:30 ; 1330 -> 13:30
                        hh = str2double(extractBetween(string(s), 1, strlength(string(s))-2));
                        mi = str2double(extractBetween(string(s), strlength(string(s))-1, strlength(string(s))));
                    end
                end
            else
                hs = strtrim(string(hora));
                % Quitar segundos si vienen
                hs = replace(hs, ".", ":");
                % Tomar HH:MM de forma tolerante
                tok = regexp(char(hs), '(\d{1,2}):(\d{2})', 'tokens', 'once');
                if ~isempty(tok)
                    hh = str2double(tok{1});
                    mi = str2double(tok{2});
                end
            end
            if isnan(hh) || isnan(mi)
                r = r + 1;
                continue;
            end

            % Normalizar ALTURA y CAUDAL (aceptar num o texto numérico)
            if isnumeric(alt); altv = alt; else; altv = str2double(string(alt)); end
            if isnumeric(q);   qv   = q;   else; qv   = str2double(string(q));   end
            if isnan(altv) || isnan(qv)
                r = r + 1;
                continue;
            end

            % Indicador (puede ser '*' o vacío)
            if isBlank(ind)
                indv = "";
            else
                indv = strtrim(string(ind));
            end

            % Construir datetime completo
            dt = datetime(yy, mm, dd, hh, mi, 0);

            % Guardar
            Fecha(end+1,1)     = dt;
            Altura(end+1,1)    = altv;
            Caudal(end+1,1)    = qv;
            Indicador(end+1,1) = indv;

            r = r + 1;
        end
    end

    % Avanzar al siguiente mes:
    % Lo más robusto: seguir escaneando desde la fila siguiente al MES actual
    % (no dependemos de filas vacías, pero respeta tu estructura)
    i = i + 1;
end

% Crear tabla final
Fecha.Format = 'yyyy-MM-dd HH:mm:ss';

T = table(Fecha, Altura, Caudal, Indicador);

% Ordenar por fecha (por si quedaron mezclas de bloques)
T = sortrows(T, "Fecha");

% Exportar CSV

writetable(T, OUT_CSV);

% Resumen rápido
fprintf('Listo. Registros exportados: %d\n', height(T));
fprintf('Salida: %s\n', OUT_CSV);
