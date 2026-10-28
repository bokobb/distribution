package com.confectionery.distribution.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Optional;
import java.util.UUID;

/**
 * Фото с телефонов (полка при визите, позже — фасад нового магазина) — файлами на диске сервера, в базе
 * только путь «компания/папка/uuid.jpg». Корень — distribution.files.dir (FILES_DIR); в git не попадает.
 * Повторная загрузка того же фото просто заменяет файл.
 */
@Service
public class FileStore {

    /** Больше не принимается: приложение сжимает фото до 1600 px — это несколько сотен КБ. */
    public static final int MAX_PHOTO = 5 * 1024 * 1024;

    private final Path root;

    public FileStore(@Value("${distribution.files.dir}") String dir) {
        this.root = Path.of(dir).toAbsolutePath().normalize();
    }

    /** Сохранить JPEG; вернуть путь для базы. */
    public String savePhoto(Long companyId, String folder, UUID uuid, byte[] jpeg) {
        if (jpeg == null || jpeg.length < 3 || (jpeg[0] & 0xff) != 0xFF || (jpeg[1] & 0xff) != 0xD8 || (jpeg[2] & 0xff) != 0xFF)
            throw new FormException("Фото — только JPEG");
        if (jpeg.length > MAX_PHOTO) throw new FormException("Фото больше 5 МБ");
        String rel = companyId + "/" + folder + "/" + uuid + ".jpg";
        Path file = root.resolve(rel);
        try {
            Files.createDirectories(file.getParent());
            Path part = Files.createTempFile(file.getParent(), uuid.toString(), ".part");
            Files.write(part, jpeg);
            Files.move(part, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return rel;
    }

    /** Файл по пути из базы; нет его или путь ведёт за пределы папки — пусто. */
    public Optional<Path> find(String rel) {
        if (rel == null || rel.isBlank()) return Optional.empty();
        Path file = root.resolve(rel).normalize();
        return file.startsWith(root) && Files.isRegularFile(file) ? Optional.of(file) : Optional.empty();
    }
}
