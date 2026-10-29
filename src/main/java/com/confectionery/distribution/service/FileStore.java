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
 * Фото с телефонов (полка при визите, фасад нового магазина, накладная или подпись при доставке) — файлами на
 * диске сервера, в базе только путь «компания/папка/uuid.jpg». Корень — distribution.files.dir (FILES_DIR); в git не попадает.
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
        if (!isJpeg(jpeg)) throw new FormException("Фото — только JPEG");
        return save(companyId + "/" + folder + "/" + uuid + ".jpg", jpeg);
    }

    /** Подтверждение доставки: подпись получателя (PNG) или фото накладной (JPEG); вернуть путь для базы. */
    public String saveProof(Long companyId, UUID uuid, byte[] image) {
        String ext = isJpeg(image) ? ".jpg" : isPng(image) ? ".png" : null;
        if (ext == null) throw new FormException("Подтверждение — только фото JPEG или подпись PNG");
        // переслали другим видом (была подпись — стало фото) — прежний файл не нужен
        for (String old : new String[]{".jpg", ".png"})
            if (!old.equals(ext)) delete(companyId + "/deliveries/" + uuid + old);
        return save(companyId + "/deliveries/" + uuid + ext, image);
    }

    private static boolean isJpeg(byte[] b) {
        return b != null && b.length >= 3 && (b[0] & 0xff) == 0xFF && (b[1] & 0xff) == 0xD8 && (b[2] & 0xff) == 0xFF;
    }

    private static boolean isPng(byte[] b) {
        return b != null && b.length >= 4 && (b[0] & 0xff) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G';
    }

    private void delete(String rel) {
        try {
            Files.deleteIfExists(root.resolve(rel));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private String save(String rel, byte[] bytes) {
        if (bytes.length > MAX_PHOTO) throw new FormException("Фото больше 5 МБ");
        Path file = root.resolve(rel);
        try {
            Files.createDirectories(file.getParent());
            Path part = Files.createTempFile(file.getParent(), file.getFileName().toString(), ".part");
            Files.write(part, bytes);
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
