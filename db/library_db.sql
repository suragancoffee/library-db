-- =========================================================
-- 도서관 대출 관리 시스템 - DB 구현 (MySQL 8)
-- 팀 프로젝트(4인)에서 설계한 9개 테이블을 MySQL에 직접 구현하고,
-- 대출·반납·연장·연체·예약·통계 SQL을 작성함
--
-- 기준 정보 : member, publisher, category, author, book_master, book_item, book_author
-- 이력 정보 : loan(대출), reservation(예약)
-- =========================================================
DROP DATABASE IF EXISTS library_db;
CREATE DATABASE library_db DEFAULT CHARACTER SET utf8mb4;
USE library_db;

-- =========================================================
-- 1. 테이블 생성 (9개)
-- =========================================================

-- 회원. PK는 시스템이 만드는 인공키(member_id), 주민등록번호는 UNIQUE로만 관리
--  * 비밀번호는 해시값(SHA2 64자리)이 들어가므로 VARCHAR(100)
--  * resident_id VARCHAR(14)는 '######-#######' 평문 길이라 암호화한 값은 담지 못함
--    (실제 서비스라면 주민등록번호는 저장하지 않거나 별도 암호화 저장소를 써야 함. 아래 샘플은 가상 값)
CREATE TABLE member (
    member_id       INT AUTO_INCREMENT PRIMARY KEY,
    resident_id     VARCHAR(14)  NOT NULL UNIQUE,
    name            VARCHAR(50)  NOT NULL,
    password        VARCHAR(100) NOT NULL,
    email           VARCHAR(100) UNIQUE,
    phone           VARCHAR(20)  NOT NULL,
    grade           VARCHAR(20)  NOT NULL DEFAULT '일반',
    join_date       DATE         NOT NULL,
    max_loan_count  INT          NOT NULL DEFAULT 5,
    CHECK (grade IN ('일반', '우수', 'VIP')),
    CHECK (max_loan_count BETWEEN 1 AND 10)
);

-- 출판사 (도서에서 분리: 출판사 정보가 바뀌어도 한 곳만 고치면 됨 = 3정규형)
CREATE TABLE publisher (
    publisher_id    INT AUTO_INCREMENT PRIMARY KEY,
    publisher_name  VARCHAR(100) NOT NULL,
    address         VARCHAR(200),
    phone           VARCHAR(20),
    email           VARCHAR(100)
);

-- 카테고리(장르)
CREATE TABLE category (
    category_id     INT AUTO_INCREMENT PRIMARY KEY,
    category_name   VARCHAR(50)  NOT NULL,
    description     VARCHAR(200)
);

-- 저자
CREATE TABLE author (
    author_id       INT AUTO_INCREMENT PRIMARY KEY,
    author_name     VARCHAR(100) NOT NULL,
    bio             VARCHAR(500)
);

-- 도서 마스터: 책 한 종류의 공통 정보 (제목, ISBN ...)
-- 삭제 규칙: 출판사·카테고리는 도서가 있으면 지울 수 없음(RESTRICT)
CREATE TABLE book_master (
    book_id         INT AUTO_INCREMENT PRIMARY KEY,
    isbn            VARCHAR(20)  NOT NULL UNIQUE,
    publisher_id    INT          NOT NULL,
    category_id     INT          NOT NULL,
    title           VARCHAR(200) NOT NULL,
    pub_year        YEAR,
    page_count      INT,
    reg_date        DATE         NOT NULL,
    FOREIGN KEY (publisher_id) REFERENCES publisher(publisher_id) ON DELETE RESTRICT,
    FOREIGN KEY (category_id)  REFERENCES category(category_id)   ON DELETE RESTRICT,
    CHECK (page_count IS NULL OR page_count > 0)
);

-- 도서 개별(복본): 서가에 실제로 꽂혀 있는 책 한 권. 바코드로 구분
--  * status         : 책의 물리적 상태 (양호 / 훼손 / 분실)
--  * loan_available : 지금 빌릴 수 있는가 (Y/N). 대출 때 N, 반납 때 Y.
--                     대출 테이블에서 계산할 수도 있지만 조회가 잦아 컬럼으로 저장해 둠
-- 삭제 규칙: 복본이 있는 도서 마스터는 지울 수 없음(RESTRICT)
CREATE TABLE book_item (
    book_item_id    INT AUTO_INCREMENT PRIMARY KEY,
    book_id         INT          NOT NULL,
    barcode         VARCHAR(50)  NOT NULL UNIQUE,
    location_shelf  VARCHAR(50),
    status          VARCHAR(20)  NOT NULL DEFAULT '양호',
    loan_available  CHAR(1)      NOT NULL DEFAULT 'Y',
    FOREIGN KEY (book_id) REFERENCES book_master(book_id) ON DELETE RESTRICT,
    CHECK (status IN ('양호', '훼손', '분실')),
    CHECK (loan_available IN ('Y', 'N'))
);

-- 도서_저자: 도서 x 저자 다대다(N:M)를 풀어 주는 교차 테이블. 복합 PK로 같은 조합의 중복을 막음
CREATE TABLE book_author (
    book_id         INT NOT NULL,
    author_id       INT NOT NULL,
    PRIMARY KEY (book_id, author_id),
    FOREIGN KEY (book_id)   REFERENCES book_master(book_id) ON DELETE CASCADE,
    FOREIGN KEY (author_id) REFERENCES author(author_id)    ON DELETE RESTRICT
);

-- 대출: 회원이 복본(book_item) 한 권을 빌릴 때마다 한 줄. 반납하면 return_date를 채움
--  * renew_count : 연장 횟수 (최대 2회로 제한)
--  * overdue_yn  : 연체 여부(Y/N). 반납예정일이 지났는데 반납하지 않았거나, 늦게 반납했을 때 Y
CREATE TABLE loan (
    loan_id         INT AUTO_INCREMENT PRIMARY KEY,
    member_id       INT     NOT NULL,
    book_item_id    INT     NOT NULL,
    loan_date       DATE    NOT NULL,
    due_date        DATE    NOT NULL,
    return_date     DATE,
    renew_count     INT     NOT NULL DEFAULT 0,
    overdue_yn      CHAR(1) NOT NULL DEFAULT 'N',
    FOREIGN KEY (member_id)    REFERENCES member(member_id)        ON DELETE RESTRICT,
    FOREIGN KEY (book_item_id) REFERENCES book_item(book_item_id)  ON DELETE RESTRICT,
    CHECK (due_date >= loan_date),
    CHECK (return_date IS NULL OR return_date >= loan_date),
    CHECK (renew_count BETWEEN 0 AND 2),
    CHECK (overdue_yn IN ('Y', 'N'))
);
-- 연체 조회·대출 중 조회가 잦아서 만든 인덱스
CREATE INDEX idx_loan_return_due ON loan (return_date, due_date);

-- 예약: 모든 복본이 대출 중인 도서(마스터 단위)에 대해 신청
CREATE TABLE reservation (
    reserve_id      INT AUTO_INCREMENT PRIMARY KEY,
    member_id       INT         NOT NULL,
    book_id         INT         NOT NULL,
    reserve_date    DATE        NOT NULL,
    reserve_status  VARCHAR(20) NOT NULL DEFAULT '대기',
    FOREIGN KEY (member_id) REFERENCES member(member_id)      ON DELETE RESTRICT,
    FOREIGN KEY (book_id)   REFERENCES book_master(book_id)   ON DELETE RESTRICT,
    CHECK (reserve_status IN ('대기', '완료', '취소'))
);

-- =========================================================
-- 2. 샘플 데이터 (모두 가상의 값)
-- =========================================================
INSERT INTO publisher (publisher_name, address, phone, email) VALUES
('한빛미디어샘플', '서울시 마포구', '02-0000-0001', 'hanbit@example.com'),
('새벽출판샘플',   '경기도 파주시', '031-000-0002', 'dawn@example.com'),
('푸른숲샘플',     '서울시 종로구', '02-0000-0003', 'forest@example.com');

INSERT INTO category (category_name, description) VALUES
('소설',   '국내외 소설'),
('비문학', '인문·사회·과학 등'),
('아동',   '어린이 도서'),
('참고서', '전공·IT 참고서');

INSERT INTO author (author_name, bio) VALUES
('김지원', '데이터베이스 강의를 해 온 저자'),
('이도윤', '자바 개발자 출신 저자'),
('박서준', 'SQL 실무서를 쓴 저자'),
('정하늘', '소설가'),
('한소라', '동화 작가');

INSERT INTO book_master (isbn, publisher_id, category_id, title, pub_year, page_count, reg_date) VALUES
('979-11-0000-001-1', 1, 4, '데이터베이스 입문',   2022, 420, '2026-03-02'),
('979-11-0000-002-2', 1, 4, '자바 프로그래밍',     2023, 560, '2026-03-02'),
('979-11-0000-003-3', 1, 4, 'SQL 실전 가이드',     2024, 380, '2026-03-02'),
('979-11-0000-004-4', 2, 1, '별빛 아래서',         2021, 310, '2026-03-05'),
('979-11-0000-005-5', 3, 3, '바다로 간 고양이',    2020, 64,  '2026-03-05'),
('979-11-0000-006-6', 3, 2, '생각의 지도',         2019, 288, '2026-03-05');

-- 한 책에 저자가 여러 명(SQL 실전 가이드), 한 저자가 여러 책(박서준, 김지원)
INSERT INTO book_author (book_id, author_id) VALUES
(1, 1), (2, 2), (3, 1), (3, 3), (4, 4), (5, 5), (6, 4);

-- 복본 9권 (데이터베이스 입문 2권, 자바 2권, SQL 1권, 별빛 2권, 고양이 1권, 생각의 지도 1권)
INSERT INTO book_item (book_id, barcode, location_shelf) VALUES
(1, 'BC-0001-1', 'A-01'), (1, 'BC-0001-2', 'A-01'),
(2, 'BC-0002-1', 'A-02'), (2, 'BC-0002-2', 'A-02'),
(3, 'BC-0003-1', 'A-03'),
(4, 'BC-0004-1', 'B-01'), (4, 'BC-0004-2', 'B-01'),
(5, 'BC-0005-1', 'C-01'),
(6, 'BC-0006-1', 'B-02');

INSERT INTO member (resident_id, name, password, email, phone, grade, join_date, max_loan_count) VALUES
('000000-0000001', '김민수', SHA2('pw-sample-1', 256), 'minsu@example.com',  '010-0000-0001', '일반', '2026-03-10', 5),
('000000-0000002', '이서연', SHA2('pw-sample-2', 256), 'seoyeon@example.com','010-0000-0002', '우수', '2026-03-12', 7),
('000000-0000003', '박지훈', SHA2('pw-sample-3', 256), 'jihun@example.com',  '010-0000-0003', 'VIP',  '2026-03-15', 10),
('000000-0000004', '최유리', SHA2('pw-sample-4', 256), 'yuri@example.com',   '010-0000-0004', '일반', '2026-04-01', 5);

-- 지난 대출 기록 (대출 중인 복본은 loan_available = 'N'으로 맞춤)
START TRANSACTION;
-- (가) 반납 기한이 지났는데 아직 안 돌려준 대출: 김민수, 데이터베이스 입문 1권째
INSERT INTO loan (member_id, book_item_id, loan_date, due_date) VALUES (1, 1, '2026-10-01', '2026-10-15');
UPDATE book_item SET loan_available = 'N' WHERE book_item_id = 1;
-- (나) 제때 반납한 대출: 박지훈, SQL 실전 가이드
INSERT INTO loan (member_id, book_item_id, loan_date, due_date, return_date) VALUES (3, 5, '2026-09-20', '2026-10-04', '2026-10-03');
-- (다) 늦게 반납한 대출: 최유리, 바다로 간 고양이 (연체 Y)
INSERT INTO loan (member_id, book_item_id, loan_date, due_date, return_date, overdue_yn) VALUES (4, 8, '2026-09-10', '2026-09-24', '2026-09-30', 'Y');
-- (라) 정상 대출 중: 이서연, 자바 프로그래밍 1권째
INSERT INTO loan (member_id, book_item_id, loan_date, due_date) VALUES (2, 3, '2026-10-26', '2026-11-09');
UPDATE book_item SET loan_available = 'N' WHERE book_item_id = 3;
COMMIT;

-- =========================================================
-- 3. 업무 SQL (대출 / 반납 / 연장 / 연체 / 예약)
--    실제 프로그램에서는 아래 SELECT로 조건을 확인한 뒤 통과할 때만 INSERT/UPDATE를 실행함
-- =========================================================

-- [연체 갱신] 반납예정일이 지났는데 반납하지 않은 대출을 연체(Y)로 표시 (매일 한 번 실행한다고 가정)
UPDATE loan
SET overdue_yn = 'Y'
WHERE return_date IS NULL
  AND due_date < CURDATE()
  AND overdue_yn = 'N';

-- [대출 가능 회원 점검] 남은 대출 권수와 연체 중인 책 수. 남은 권수 > 0 이고 연체중 = 0 이어야 대출 가능
SELECT m.member_id, m.name, m.max_loan_count,
       COUNT(CASE WHEN l.return_date IS NULL THEN 1 END) AS 현재대출수,
       m.max_loan_count - COUNT(CASE WHEN l.return_date IS NULL THEN 1 END) AS 남은권수,
       COUNT(CASE WHEN l.return_date IS NULL AND l.overdue_yn = 'Y' THEN 1 END) AS 연체중
FROM member m
LEFT JOIN loan l ON l.member_id = m.member_id
GROUP BY m.member_id, m.name, m.max_loan_count
ORDER BY m.member_id;

-- [대출] 박지훈(3)이 '자바 프로그래밍' 2권째(book_item 4)를 빌림
--   복본 행을 잠가서(FOR UPDATE) 같은 책을 두 사람이 동시에 빌리지 못하게 하고,
--   대출 INSERT와 대출가능여부 UPDATE를 한 트랜잭션으로 묶음
SET @member_id = 3;
SET @item_id   = 4;
START TRANSACTION;
SELECT loan_available FROM book_item WHERE book_item_id = @item_id FOR UPDATE;   -- 'Y'일 때만 진행
INSERT INTO loan (member_id, book_item_id, loan_date, due_date)
VALUES (@member_id, @item_id, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY));
UPDATE book_item SET loan_available = 'N' WHERE book_item_id = @item_id AND loan_available = 'Y';
COMMIT;

-- [연장] 방금 빌린 대출을 7일 연장. 반납 전 + 연체 아님 + 연장 2회 미만일 때만 바뀜 (바뀐 행이 0이면 연장 불가)
SET @loan_id = (SELECT MAX(loan_id) FROM loan WHERE member_id = 3 AND book_item_id = 4);
UPDATE loan
SET due_date = DATE_ADD(due_date, INTERVAL 7 DAY),
    renew_count = renew_count + 1
WHERE loan_id = @loan_id
  AND return_date IS NULL
  AND overdue_yn = 'N'
  AND renew_count < 2;
SELECT ROW_COUNT() AS 연장된행수;

-- [반납] 이서연(2)이 빌린 '자바 프로그래밍' 1권째(book_item 3)를 반납
--   반납일 기록 + 연체 여부 판정 + 대출가능여부 'Y'로 복귀를 한 트랜잭션으로 묶음
START TRANSACTION;
UPDATE loan
SET return_date = CURDATE(),
    overdue_yn  = CASE WHEN CURDATE() > due_date THEN 'Y' ELSE 'N' END
WHERE member_id = 2 AND book_item_id = 3 AND return_date IS NULL;
UPDATE book_item SET loan_available = 'Y' WHERE book_item_id = 3;
COMMIT;

-- [예약] '생각의 지도'(book 6, 복본 1권)를 최유리(4)가 빌린 뒤, 이서연(2)이 예약
START TRANSACTION;
INSERT INTO loan (member_id, book_item_id, loan_date, due_date)
VALUES (4, 9, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY));
UPDATE book_item SET loan_available = 'N' WHERE book_item_id = 9;
COMMIT;

--   빌릴 수 있는 복본이 하나도 없을 때만 예약이 등록됨 (있으면 바로 대출하면 되므로 0건)
INSERT INTO reservation (member_id, book_id, reserve_date, reserve_status)
SELECT 2, 6, CURDATE(), '대기'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM book_item WHERE book_id = 6 AND loan_available = 'Y');

-- =========================================================
-- 4. 조회·통계 SQL
-- =========================================================

-- [현재 대출 현황] 누가 어떤 책을 언제까지 빌렸는지 (6개 테이블 JOIN)
SELECT l.loan_id, m.name AS 회원, b.title AS 도서, bi.barcode, l.loan_date, l.due_date, l.renew_count AS 연장횟수, l.overdue_yn AS 연체
FROM loan l
JOIN member m       ON m.member_id    = l.member_id
JOIN book_item bi   ON bi.book_item_id = l.book_item_id
JOIN book_master b  ON b.book_id      = bi.book_id
WHERE l.return_date IS NULL
ORDER BY l.due_date;

-- [연체 목록] 연체일수 = 오늘 - 반납예정일
SELECT m.name AS 회원, m.phone AS 연락처, b.title AS 도서, l.due_date AS 반납예정일,
       DATEDIFF(CURDATE(), l.due_date) AS 연체일수
FROM loan l
JOIN member m       ON m.member_id     = l.member_id
JOIN book_item bi   ON bi.book_item_id = l.book_item_id
JOIN book_master b  ON b.book_id       = bi.book_id
WHERE l.return_date IS NULL AND l.due_date < CURDATE()
ORDER BY 연체일수 DESC;

-- [도서별 대출 횟수 TOP 3] 복본(book_item)이 아니라 도서 마스터 기준으로 합침
SELECT b.title AS 도서, COUNT(*) AS 대출횟수
FROM loan l
JOIN book_item bi   ON bi.book_item_id = l.book_item_id
JOIN book_master b  ON b.book_id       = bi.book_id
GROUP BY b.book_id, b.title
ORDER BY 대출횟수 DESC, b.title
LIMIT 3;

-- [카테고리별 대출 통계] 카테고리를 별도 테이블로 분리했기 때문에 쉽게 뽑을 수 있음
SELECT c.category_name AS 카테고리, COUNT(l.loan_id) AS 대출건수
FROM category c
LEFT JOIN book_master b  ON b.category_id  = c.category_id
LEFT JOIN book_item bi   ON bi.book_id     = b.book_id
LEFT JOIN loan l         ON l.book_item_id = bi.book_item_id
GROUP BY c.category_id, c.category_name
ORDER BY 대출건수 DESC, c.category_name;

-- [회원별 누적 대출 횟수] 2회 이상 빌린 회원만 (묶은 뒤 조건이라 WHERE가 아니라 HAVING)
SELECT m.name AS 회원, m.grade AS 등급, COUNT(l.loan_id) AS 누적대출
FROM member m
JOIN loan l ON l.member_id = m.member_id
GROUP BY m.member_id, m.name, m.grade
HAVING COUNT(l.loan_id) >= 2
ORDER BY 누적대출 DESC, m.name;

-- [도서별 복본 수와 대출 가능 권수]
SELECT b.title AS 도서,
       COUNT(bi.book_item_id) AS 전체복본,
       SUM(CASE WHEN bi.loan_available = 'Y' THEN 1 ELSE 0 END) AS 대출가능
FROM book_master b
JOIN book_item bi ON bi.book_id = b.book_id
GROUP BY b.book_id, b.title
ORDER BY b.book_id;

-- [도서별 저자] 다대다(N:M) 교차 테이블(book_author)을 거쳐 공동 저자를 한 줄로 합침
SELECT b.title AS 도서, GROUP_CONCAT(a.author_name ORDER BY a.author_id SEPARATOR ', ') AS 저자
FROM book_master b
JOIN book_author ba ON ba.book_id   = b.book_id
JOIN author a       ON a.author_id  = ba.author_id
GROUP BY b.book_id, b.title
ORDER BY b.book_id;

-- [월별 대출 건수]
SELECT DATE_FORMAT(loan_date, '%Y-%m') AS 월, COUNT(*) AS 대출건수
FROM loan
GROUP BY DATE_FORMAT(loan_date, '%Y-%m')
ORDER BY 월;

-- [예약 대기 목록]
SELECT r.reserve_id, m.name AS 회원, b.title AS 도서, r.reserve_date, r.reserve_status
FROM reservation r
JOIN member m       ON m.member_id = r.member_id
JOIN book_master b  ON b.book_id   = r.book_id
WHERE r.reserve_status = '대기'
ORDER BY r.reserve_date, r.reserve_id;

-- =========================================================
-- 5. 무결성 확인 (직접 실행해 보세요. 아래는 오류가 나는 것이 정상입니다)
-- =========================================================
-- DELETE FROM book_master WHERE book_id = 1;   -- 복본이 있어서 삭제 불가 (ON DELETE RESTRICT)
-- INSERT INTO book_author (book_id, author_id) VALUES (3, 3);   -- 같은 도서·저자 조합 중복 (복합 PK)
-- INSERT INTO member (resident_id, name, password, phone, join_date) VALUES ('000000-0000001', '중복', 'x', '010', CURDATE());   -- 주민번호 UNIQUE
-- UPDATE loan SET renew_count = 3 WHERE loan_id = 1;   -- 연장은 최대 2회 (CHECK)
