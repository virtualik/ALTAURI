package core.io;

// ============================================================================
// PathCanon v1.0 — канонизация путей записи (Этап 3 «Кнопка [Export]», Task 137)
// ----------------------------------------------------------------------------
// ЛЕКСИЧЕСКИЙ канонизатор: приводит путь к сравнимой форме ДО сопоставления
// с Sys.programPath()/base/источниками истины.
//
// ИСТОРИЧЕСКАЯ ПРИЧИНА (урок T-EMB.7, Этап 1): строковый guard писателя
// пропускал ОТНОСИТЕЛЬНЫЙ путь — «ALTAURI_Windows.exe», набранный в папке
// самого exe, строкой не равен «C:\...\bin\ALTAURI_Windows.exe»; приберегла
// ОС (sharing violation, код 1 с невнятным «io error»). Теперь срабатывает
// канонический предохранитель В КОДЕ, с внятным сообщением.
//
// ПРАВИЛА КАНОНИЗАЦИИ (чистая лексика, без запросов к ФС):
//   1. null/пусто → "";
//   2. префиксы Win32-пространств имён «\\?\» / «\\.\» срезаются
//      («\\?\UNC\» → «\\»);
//   3. разделители унифицируются в «/»;
//   4. относительный путь достраивается от Sys.getCwd() (или cwd-аргумента
//      теста);
//   5. сегменты «.» и пустые (двойные слэши) отбрасываются; «..» съедает
//      предыдущий сегмент, над корнем — съедается сам;
//   6. хвостовые слэши срезаются (кроме корней «C:/» и «/»);
//   7. РЕГИСТР: samePath() на Windows сравнивает без учёта регистра, на
//      прочих таргетах — честно (ci-аргумент перекрывает для тестов).
//      canonical() НИКОГДА не меняет регистр — форма остаётся без потерь.
//
// ЧТО КАНОНИЗАТОР НЕ ДЕЛАЕТ (v1-честность, задокументировано):
//   · НЕ резолвит 8.3-имена (PROGRA~1), symlinks/junctions, SUBST-диски —
//     это запрос к файловой системе; осевой предохранитель ОС (запрет
//     записи в работающий exe) остаётся последней линией обороны;
//   · НЕ проверяет существование пути — только текст.
//
// Дисциплина: pure-функция от строки (+ опциональный cwd). На несис-
// таргетах не компилируется (не референсится вне #if sys-кода).
// ============================================================================

class PathCanon
{
        /**
         * Каноническая форма: абсолютная, «/»-разделители, без «./..»,
         * без хвостовых слэшей. Регистр сохранён (сравнение — samePath).
         * @param path исходный путь (null/пусто → "")
         * @param cwd  рабочий каталог для достройки относительных путей;
         *             null = Sys.getCwd() (тесты подставляют свой)
         */
        public static function canonical(path:String, ?cwd:String):String
        {
                if (path == null || path.length == 0) return "";

                var p:String = path;

                // ── 1) Win32-префиксы пространств имён ──────────────────
                if (StringTools.startsWith(p, "\\\\?\\UNC\\"))
                        p = "\\" + p.substr(8);
                else if (StringTools.startsWith(p, "\\\\?\\"))
                        p = p.substr(4);
                else if (StringTools.startsWith(p, "\\\\.\\"))
                        p = p.substr(4);

                // ── 2) унификация разделителей ──────────────────────────
                p = StringTools.replace(p, "\\", "/");

                // ── 3) достройка относительных путей ────────────────────
                if (!_isAbsolute(p))
                {
                        var base:String = (cwd != null) ? cwd : _sysCwd();
                        base = StringTools.replace(base, "\\", "/");
                        if (base.length > 0 && !StringTools.endsWith(base, "/")) base += "/";
                        p = base + p;
                }

                // ── 4) разбор сегментов ─────────────────────────────────
                var parts:Array<String> = p.split("/");

                // корень: «C:/…» → префикс «C:/»; «/…» → «/»; «//srv/…» → «//»
                var prefix:String = "";
                var first:Int = 0;
                if (parts.length > 0 && _isDrive(parts[0]))
                {
                        prefix = parts[0] + "/";
                        first = 1;
                }
                else if (StringTools.startsWith(p, "//"))
                {
                        prefix = "//";
                        first = 1;   // parts[0] == "" — съедается префиксом
                }
                else if (StringTools.startsWith(p, "/"))
                {
                        prefix = "/";
                        first = 1;   // parts[0] == "" — съедается префиксом
                }

                var out:Array<String> = [];
                var i:Int = first;
                while (i < parts.length)
                {
                        var seg:String = parts[i];
                        if (seg == "" || seg == ".")
                        {
                                // пустые сегменты и «.» — мусор
                        }
                        else if (seg == "..")
                        {
                                if (out.length > 0) out.pop();
                                // «..» над корнем — съедается молча: выше
                                // корня путей не бывает
                        }
                        else
                        {
                                out.push(seg);
                        }
                        i++;
                }

                var joined:String = out.join("/");
                if (prefix == "")
                {
                        // теория: неабсолютный путь при пустом cwd — остаётся
                        // как есть (хвостовые слэши уже срезаны split/join)
                        return joined;
                }
                return prefix + joined;
        }

        /**
         * Сравнение путей записи в канонических формах.
         * @param caseInsensitive null = авто (#if windows → да); тесты на
         *                         Linux подставляют true для Windows-форм
         * @param cwd             рабочий каталог для обеих сторон (тесты)
         */
        public static function samePath(a:String, b:String,
                        ?caseInsensitive:Null<Bool>, ?cwd:String):Bool
        {
                if (a == null || b == null) return false;
                // Null<Bool> → Bool БЕЗ null-литерала: на статических
                // платформах (cpp/hl) null для базового типа Bool
                // нелегален (поле Станции: PathCanon 139/160, Task 138).
                var ci:Bool = (caseInsensitive != null) ? caseInsensitive : _isWindows();
                var x:String = canonical(a, cwd);
                var y:String = canonical(b, cwd);
                if (ci)
                {
                        x = x.toLowerCase();
                        y = y.toLowerCase();
                }
                return x == y;
        }

        /**
         * Находится ли путь ВНУТРИ каталога (строго ниже, не сам каталог).
         * Сравнение канонических форм с разделителем на конце — ловушка
         * префикса («C:/xlib» не внутри «C:/x/lib») исключена.
         */
        public static function isInsideDir(path:String, dir:String,
                        ?caseInsensitive:Null<Bool>, ?cwd:String):Bool
        {
                if (path == null || dir == null) return false;
                // Null<Bool> → Bool БЕЗ null-литерала: на статических
                // платформах (cpp/hl) null для базового типа Bool
                // нелегален (поле Станции: PathCanon 139/160, Task 138).
                var ci:Bool = (caseInsensitive != null) ? caseInsensitive : _isWindows();
                var p:String = canonical(path, cwd);
                var d:String = canonical(dir, cwd);
                if (ci)
                {
                        p = p.toLowerCase();
                        d = d.toLowerCase();
                }
                if (d == "" || d == "/") return true;  // корень объемлет всё
                if (!StringTools.endsWith(d, "/")) d += "/";
                return StringTools.startsWith(p, d);
        }

        /**
         * Каталог пути БЕЗ канонизации (орфография сохранена — пригодна
         * для нативных API). Ищет последний разделитель любого рода.
         * «C:\a\b\c.exe» → «C:\a\b»; «c.exe» → «»; «/x» → «/».
         */
        public static function dirname(path:String):String
        {
                if (path == null) return "";
                var i1:Int = path.lastIndexOf("/");
                var i2:Int = path.lastIndexOf("\\");
                var idx:Int = (i1 > i2) ? i1 : i2;
                if (idx < 0) return "";
                if (idx == 0) return path.charAt(0);   // «/x» → «/»
                return path.substr(0, idx);
        }

        // ── Внутренняя кухня ──────────────────────────────────────────────

        /** Абсолютность после унификации слэшей: «/…» или «X:/…». */
        private static function _isAbsolute(p:String):Bool
        {
                if (StringTools.startsWith(p, "/")) return true;   // включая UNC «//»
                if (p.length >= 3 && _isDrive(p.substr(0, 2)) && p.charAt(2) == "/")
                        return true;
                // «C:file» (drive-relative, курьёз Windows) канонизируется
                // как относительный — v1-честность задокументирована
                return false;
        }

        /** Сегмент вида «C:» (латинская буква + двоеточие). */
        private static inline function _isDrive(s:String):Bool
        {
                if (s == null || s.length != 2) return false;
                var c:Int = s.charCodeAt(0);
                var d:Int = s.charCodeAt(1);
                var letter:Bool = (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
                return letter && d == 58;   // ':'
        }

        private static function _sysCwd():String
        {
                try { return Sys.getCwd(); } catch (e:Dynamic) { return ""; }
        }

        private static inline function _isWindows():Bool
        {
                #if windows
                return true;
                #else
                return false;
                #end
        }
}
